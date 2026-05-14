import AppKit
import Foundation

class FileSaveService {
    func save(image: NSImage) throws -> URL {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw FileSaveError.conversionFailed
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "Screenshot-\(timestamp).png"

        let folderURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("Screenshot")

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let fileURL = folderURL.appendingPathComponent(filename)
        try pngData.write(to: fileURL)
        return fileURL
    }
}

enum FileSaveError: Error {
    case conversionFailed
}
