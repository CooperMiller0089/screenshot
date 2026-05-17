import AppKit

class ClipboardService {
    func copy(image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let rep  = NSBitmapImageRep(data: tiff) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        if let png = rep.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        pasteboard.setData(tiff, forType: .tiff)
    }
}
