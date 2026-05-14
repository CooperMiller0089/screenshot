import AppKit
import Carbon

// MARK: - ScrollCaptureController
//
// Scroll strategy: advance by 35% of the frame height per step.
// This guarantees ≥35% overlap between consecutive frames, giving the
// template matcher plenty of signal to find the exact seam.
//
// Stitch strategy: for every pair (prev, curr), render both at 15% of
// original size and slide the bottom-40%-of-prev template over the top
// 80% of curr to find the best-matching row offset. That offset tells us
// exactly how many pixels of curr are already in prev, so we append only
// the genuinely new (bottom) portion — no gaps, no duplicates.

@MainActor
class ScrollCaptureController {
    static let shared = ScrollCaptureController()

    private(set) var isActive = false
    private var captureRect: CGRect = .zero
    private var frames: [NSImage] = []
    private var lastThumb: [UInt8] = []
    private var captureLoop: Task<Void, Never>?
    private var escHotkeyRef: EventHotKeyRef?
    private var escHandlerRef: EventHandlerRef?
    private var onComplete: ((NSImage?) -> Void)?

    private let screenshotService = ScreenshotService()
    private let regionCaptureService = RegionCaptureService()

    private static let escSig = OSType(0x5343454B) // "SCEK"

    // MARK: - Entry point

    func beginCapturing(rect: CGRect, baseImage: NSImage, targetApp: NSRunningApplication? = nil, completion: @escaping (NSImage?) -> Void) {
        guard !isActive else { return }
        isActive = true
        captureRect = rect
        frames = []
        lastThumb = []
        onComplete = completion

        registerEscHotkey()
        ScrollToastController.shared.show("滚动截屏中……按 ESC 停止")

        if let first = try? regionCaptureService.captureRegion(rect: rect, from: baseImage) {
            frames.append(first)
            lastThumb = makeThumb(first)
        }

        captureLoop = Task {
            // 激活目标 App，确保滚动事件发到正确窗口
            targetApp?.activate(options: .activateIgnoringOtherApps)
            try? await Task.sleep(for: .milliseconds(400))
            self.warpCursor(to: self.captureRect)

            var unchangedCount = 0
            while !Task.isCancelled && self.isActive {
                await self.smoothScroll(totalPoints: self.captureRect.height * 0.35)
                try? await Task.sleep(for: .milliseconds(250))
                guard self.isActive else { break }

                guard let full = try? await self.screenshotService.captureFullScreen(),
                      let region = try? self.regionCaptureService.captureRegion(
                          rect: self.captureRect, from: full)
                else { continue }

                let thumb = self.makeThumb(region)
                if self.contentChanged(from: self.lastThumb, to: thumb) {
                    self.frames.append(region)
                    self.lastThumb = thumb
                    unchangedCount = 0
                } else {
                    unchangedCount += 1
                    if unchangedCount >= 3 { break }  // 连续 3 次无变化 = 到达底部
                }
            }
            self.finish()
        }
    }

    // MARK: - Smooth scrolling

    private func warpCursor(to rect: CGRect) {
        guard let screenH = NSScreen.main?.frame.height else { return }
        CGWarpMouseCursorPosition(CGPoint(x: rect.midX, y: screenH - rect.midY))
    }

    private func smoothScroll(totalPoints: CGFloat) async {
        let steps = 10
        let step  = totalPoints / CGFloat(steps)
        for _ in 0..<steps {
            let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: -Int32(step),
                wheel2: 0, wheel3: 0
            )
            event?.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    // MARK: - Stop

    func finish() {
        guard isActive else { return }
        isActive = false
        captureLoop?.cancel()
        captureLoop = nil
        unregisterEscHotkey()

        let cb = onComplete; onComplete = nil
        guard !frames.isEmpty else {
            ScrollToastController.shared.hide()
            cb?(nil)
            return
        }
        ScrollToastController.shared.show("滚动截屏完成", autoDismiss: true)
        cb?(stitchWithOverlap(frames))
    }

    func cancel() {
        guard isActive else { return }
        isActive = false
        captureLoop?.cancel()
        captureLoop = nil
        unregisterEscHotkey()
        ScrollToastController.shared.hide()
        onComplete?(nil); onComplete = nil
    }

    // MARK: - ESC hotkey (Carbon, no Input Monitoring needed)

    private func registerEscHotkey() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )
        // Installed after HotkeyService's handler (LIFO) so it runs first.
        // Returns eventNotHandledErr for non-SCEK signatures so existing
        // full-screen / region shortcuts still work.
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hkID = EventHotKeyID()
                GetEventParameter(event,
                                  EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
                guard hkID.signature == 0x5343454B else {
                    return OSStatus(eventNotHandledErr)
                }
                Task { @MainActor in ScrollCaptureController.shared.finish() }
                return noErr
            },
            1, &spec, nil, &escHandlerRef
        )
        let hkID = EventHotKeyID(signature: ScrollCaptureController.escSig, id: 1)
        RegisterEventHotKey(53, 0, hkID, GetApplicationEventTarget(), 0, &escHotkeyRef)
    }

    private func unregisterEscHotkey() {
        if let r = escHotkeyRef  { UnregisterEventHotKey(r); escHotkeyRef  = nil }
        if let r = escHandlerRef { RemoveEventHandler(r);    escHandlerRef = nil }
    }

    // MARK: - Dedup (64×64 thumbnail, middle-zone comparison)

    private let thumbW = 64, thumbH = 64

    private func makeThumb(_ image: NSImage) -> [UInt8] {
        let w = thumbW, h = thumbH
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        guard let ptr = ctx.data else { return [] }
        return Array(UnsafeBufferPointer(
            start: ptr.assumingMemoryBound(to: UInt8.self), count: w * h * 4))
    }

    private func contentChanged(from a: [UInt8], to b: [UInt8]) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return true }
        let rowStart = thumbH * 2 / 10
        let rowEnd   = thumbH * 8 / 10
        let zone = (rowEnd - rowStart) * thumbW
        var changed = 0
        for row in rowStart..<rowEnd {
            for col in 0..<thumbW {
                let i = (row * thumbW + col) * 4
                let d = abs(Int(a[i]) - Int(b[i]))
                      + abs(Int(a[i+1]) - Int(b[i+1]))
                      + abs(Int(a[i+2]) - Int(b[i+2]))
                if d > 20 { changed += 1 }
            }
        }
        return changed * 10 > zone
    }

    // MARK: - Overlap-aware stitch

    // For each pair (prev, curr):
    //   1. Find `overlap` = number of pixels from the TOP of curr that already
    //      appear in prev (via template matching at 15% scale).
    //   2. Keep only the BOTTOM (curr.height − overlap) pixels of curr.
    // The result has no duplicated content and no gaps.
    private func stitchWithOverlap(_ images: [NSImage]) -> NSImage {
        guard !images.isEmpty else { return NSImage() }
        guard images.count > 1  else { return images[0] }

        // Build list of (source image, how many points from the BOTTOM to include).
        // Use Int heights so strip boundaries always fall on whole-point boundaries,
        // which prevents sub-point interpolation seams on Retina displays.
        // NSImage y=0 is the visual bottom → bottom pixels = newly revealed content.
        var strips: [(src: NSImage, height: Int)] = [
            (images[0], Int(images[0].size.height))   // first frame: include everything
        ]
        for i in 1..<images.count {
            let overlap   = findVerticalOverlap(prev: images[i-1], next: images[i])
            let newHeight = Int(images[i].size.height) - overlap
            if newHeight > 1 { strips.append((images[i], newHeight)) }
        }

        let totalH = strips.reduce(0) { $0 + $1.height }
        let width  = strips.map { $0.src.size.width }.max() ?? 0

        let result = NSImage(size: NSSize(width: width, height: CGFloat(totalH)))
        result.lockFocus()

        // Draw from top of result downward.
        // NSImage origin is bottom-left, so the first strip goes at the highest Y.
        var y = totalH
        for (src, h) in strips {
            y -= h
            // srcRect selects the bottom `h` points of the source frame:
            //   NSImage y=0 = screen bottom = newly revealed content.
            let srcRect = NSRect(x: 0, y: 0,          width: src.size.width, height: CGFloat(h))
            let dstRect = NSRect(x: 0, y: CGFloat(y), width: src.size.width, height: CGFloat(h))
            src.draw(in: dstRect, from: srcRect, operation: .copy, fraction: 1.0)
        }

        result.unlockFocus()
        return result
    }

    // MARK: - Template matching

    // Returns the number of pixels from the TOP of `next` that are already
    // present at the BOTTOM of `prev` (i.e. the overlap height in full-res points).
    //
    // Algorithm (all coords in CGContext pixel space, origin = TOP-LEFT):
    //   template  = bottom 40% of prev rendered at 15% scale (rows [60%, 100%))
    //   search    = top 80% of next rendered at 15% scale
    //   slide template over search, find row with minimum SAD
    //   overlap = (0.4·ph + bestOffset) / scale  (derived algebraically from scroll geometry)
    private func findVerticalOverlap(prev: NSImage, next: NSImage) -> Int {
        let scale = 0.15
        let pw = max(1, Int(prev.size.width  * scale))
        let ph = max(1, Int(prev.size.height * scale))
        let nw = max(1, Int(next.size.width  * scale))
        let nh = max(1, Int(next.size.height * scale))

        guard let prevPix = renderPixels(image: prev, w: pw, h: ph),
              let nextPix = renderPixels(image: next, w: nw, h: nh)
        else {
            return Int(prev.size.height * 0.35)  // fallback
        }

        let templateStart = Int(Double(ph) * 0.6)   // row 60% from top (in CGContext top-left)
        let templateH     = ph - templateStart        // covers bottom 40% of prev
        guard templateH > 0 else { return 0 }

        let searchEnd = min(Int(Double(nh) * 0.8), nh - templateH)
        guard searchEnd > 0 else { return 0 }

        let cols = min(pw, nw)
        var bestOffset = 0
        var bestSAD    = Int.max

        for offset in 0..<searchEnd {
            var sad = 0
            for row in 0..<templateH {
                let pr = templateStart + row
                let nr = offset + row
                for col in 0..<cols {
                    let pi = (pr * pw + col) * 4
                    let ni = (nr * nw + col) * 4
                    guard pi + 2 < prevPix.count, ni + 2 < nextPix.count else { continue }
                    sad += abs(Int(prevPix[pi])   - Int(nextPix[ni]))
                    sad += abs(Int(prevPix[pi+1]) - Int(nextPix[ni+1]))
                    sad += abs(Int(prevPix[pi+2]) - Int(nextPix[ni+2]))
                }
                if sad >= bestSAD { break }   // early exit if already worse
            }
            if sad < bestSAD { bestSAD = sad; bestOffset = offset }
        }

        // Algebraic derivation:
        //   template in prev starts at templateStart (row 60% from visual top)
        //   template in next starts at bestOffset
        //   rows 0..(bestOffset + templateH) of next are already in prev
        //   overlap = (templateH + bestOffset) / scale  (in point units)
        // Use templateH (not Int(0.4·ph)) to avoid rounding disagreement,
        // and ceil to ensure we never leave a partial-row ghost.
        let scaledSkip  = templateH + bestOffset
        let fullResSkip = Int(ceil(Double(scaledSkip) / scale))
        return min(fullResSkip, Int(prev.size.height) - 1)
    }

    // Render NSImage into a w×h CGContext pixel buffer (origin = top-left).
    private func renderPixels(image: NSImage, w: Int, h: Int) -> [UInt8]? {
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        guard let ptr = ctx.data else { return nil }
        return Array(UnsafeBufferPointer(
            start: ptr.assumingMemoryBound(to: UInt8.self), count: w * h * 4))
    }
}
