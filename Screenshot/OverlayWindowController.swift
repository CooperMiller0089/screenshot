import AppKit

@MainActor
class OverlayWindowController {
    static let shared = OverlayWindowController()

    private var panel: NSPanel?
    private var completion: ((CGRect?) -> Void)?

    func show(baseImage: NSImage, completion: @escaping (CGRect?) -> Void) {
        self.completion = completion

        guard let screen = NSScreen.main else { completion(nil); return }

        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.acceptsMouseMovedEvents = true
        panel.hasShadow = false

        let selectionView = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        selectionView.baseImage = baseImage
        selectionView.onComplete = { [weak self] rect in self?.dismiss(with: rect) }
        selectionView.onCancel   = { [weak self] in self?.dismiss(with: nil) }
        panel.contentView = selectionView

        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        selectionView.window?.makeFirstResponder(selectionView)
    }

    private func dismiss(with rect: CGRect?) {
        panel?.orderOut(nil)
        panel = nil
        let cb = completion
        completion = nil
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            cb?(rect)
        }
    }
}

// MARK: - SelectionView

class SelectionView: NSView {
    var baseImage: NSImage?
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var selectionRect: NSRect = .zero
    private var isDragging = false

    // Linear accent #5e6ad2
    private let accentColor = NSColor(srgbRed: 94/255, green: 106/255, blue: 210/255, alpha: 1)
    private let surfaceColor = NSColor(srgbRed: 15/255, green: 16/255, blue: 17/255, alpha: 0.88)
    private let hairlineColor = NSColor(srgbRed: 35/255, green: 37/255, blue: 42/255, alpha: 1)
    private let inkColor = NSColor(srgbRed: 247/255, green: 248/255, blue: 248/255, alpha: 1)

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Frozen background
        baseImage?.draw(in: bounds)

        // Dim overlay
        NSColor(white: 0, alpha: 0.4).setFill()
        bounds.fill()

        guard isDragging else { return }

        // Restore selection area to undimmed
        baseImage?.draw(in: selectionRect, from: selectionRect, operation: .copy, fraction: 1.0)

        // Subtle inner shadow on selection edges
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.25)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = .zero
        shadow.set()

        // Accent selection border
        accentColor.setStroke()
        let border = NSBezierPath(rect: selectionRect)
        border.lineWidth = 1.5
        border.stroke()

        // Corner accent marks (4×4 squares at each corner)
        accentColor.setFill()
        let cs: CGFloat = 4
        let corners: [NSRect] = [
            NSRect(x: selectionRect.minX - cs/2, y: selectionRect.minY - cs/2, width: cs, height: cs),
            NSRect(x: selectionRect.maxX - cs/2, y: selectionRect.minY - cs/2, width: cs, height: cs),
            NSRect(x: selectionRect.minX - cs/2, y: selectionRect.maxY - cs/2, width: cs, height: cs),
            NSRect(x: selectionRect.maxX - cs/2, y: selectionRect.maxY - cs/2, width: cs, height: cs),
        ]
        for r in corners { NSBezierPath(rect: r).fill() }

        // Size label — dark pill with hairline border
        let labelStr = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        let textAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: inkColor]
        let textSize = (labelStr as NSString).size(withAttributes: textAttrs)
        let pillW = textSize.width + 14
        let pillH = textSize.height + 6
        let pillX = selectionRect.minX
        let pillY = selectionRect.maxY + 6

        let pillRect = NSRect(x: pillX, y: pillY, width: pillW, height: pillH)
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 4, yRadius: 4)

        surfaceColor.setFill()
        pillPath.fill()
        hairlineColor.setStroke()
        pillPath.lineWidth = 0.5
        pillPath.stroke()

        let textOrigin = NSPoint(x: pillX + 7, y: pillY + 3)
        labelStr.draw(at: textOrigin, withAttributes: textAttrs)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        selectionRect = .zero
        isDragging = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let cur = convert(event.locationInWindow, from: nil)
        selectionRect = NSRect(
            x: min(start.x, cur.x), y: min(start.y, cur.y),
            width: abs(cur.x - start.x), height: abs(cur.y - start.y)
        )
        isDragging = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        if selectionRect.width < 5 || selectionRect.height < 5 { onCancel?(); return }
        onComplete?(selectionRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }
}
