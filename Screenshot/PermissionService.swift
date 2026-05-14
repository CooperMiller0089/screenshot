import AppKit
import ApplicationServices

class PermissionService {
    func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    // Accessibility permission is required for CGEventPost to send scroll events
    // to other applications (Chrome, PDF Expert, etc.).
    func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    // Shows the system dialog asking the user to add the app to the AX list.
    // The app must be restarted for the grant to take effect.
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
