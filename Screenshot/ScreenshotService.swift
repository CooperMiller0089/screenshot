import AppKit
import ScreenCaptureKit

class ScreenshotService {
    func captureFullScreen() async throws -> NSImage {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw error.isSCPermissionError ? CaptureError.permissionDenied : error
        }

        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width * 2
        config.height = display.height * 2
        config.scalesToFit = false

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        let pointSize = NSSize(width: display.width, height: display.height)
        return NSImage(cgImage: cgImage, size: pointSize)
    }
}

enum CaptureError: Error {
    case noDisplay
    case captureFailed
    case permissionDenied
}

extension Error {
    var isSCPermissionError: Bool {
        let ns = self as NSError
        return ns.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" ||
               ns.code == -3801 // SCStreamError.userDeclined
    }
}
