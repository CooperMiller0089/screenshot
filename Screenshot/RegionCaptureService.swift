import AppKit

class RegionCaptureService {
    func captureRegion(rect: CGRect, from baseImage: NSImage) throws -> NSImage {
        let cropped = NSImage(size: rect.size)
        cropped.lockFocus()
        baseImage.draw(
            in: NSRect(origin: .zero, size: rect.size),
            from: rect,
            operation: .copy,
            fraction: 1.0
        )
        cropped.unlockFocus()
        return cropped
    }
}
