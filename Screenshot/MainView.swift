import AppKit
import Combine
import SwiftUI

// MARK: - Linear palette

private extension Color {
    static let lCanvas       = Color(red: 1/255,   green: 1/255,   blue: 2/255)
    static let lSurface1     = Color(red: 15/255,  green: 16/255,  blue: 17/255)
    static let lSurface2     = Color(red: 20/255,  green: 21/255,  blue: 22/255)
    static let lSurface3     = Color(red: 24/255,  green: 25/255,  blue: 26/255)
    static let lHairline     = Color(red: 35/255,  green: 37/255,  blue: 42/255)
    static let lHairlineStrong = Color(red: 52/255, green: 52/255, blue: 58/255)
    static let lInk          = Color(red: 247/255, green: 248/255, blue: 248/255)
    static let lInkMuted     = Color(red: 208/255, green: 214/255, blue: 224/255)
    static let lInkSubtle    = Color(red: 138/255, green: 143/255, blue: 152/255)
    static let lInkTertiary  = Color(red: 98/255,  green: 102/255, blue: 109/255)
    static let lAccent       = Color(red: 94/255,  green: 106/255, blue: 210/255)
    static let lAccentHover  = Color(red: 130/255, green: 143/255, blue: 255/255)
}

// MARK: - Button styles

private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.lInk)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(configuration.isPressed ? Color.lAccentHover : Color.lAccent)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(isEnabled ? 1 : 0.38)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(configuration.isPressed ? .lInk : .lInkMuted)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(configuration.isPressed ? Color.lSurface3 : Color.lSurface2)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.lHairline, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.38)
    }
}

private struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11))
            .foregroundColor(configuration.isPressed ? .lInkSubtle : .lInkTertiary)
    }
}

// MARK: - MainViewModel

@MainActor
class MainViewModel: ObservableObject {
    @Published var statusMessage: String = "准备就绪"
    @Published var isCapturing: Bool = false
    @Published var showPermissionButton: Bool = false

    private var pendingPermissionURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

    private let screenshotService = ScreenshotService()
    private let regionCaptureService = RegionCaptureService()
    private let fileSaveService = FileSaveService()
    private let clipboardService = ClipboardService()

    func setupHotkeys() {
        let hotkeys = HotkeyService.shared
        hotkeys.onFullScreen = { [weak self] in self?.captureFullScreen() }
        hotkeys.onRegion     = { [weak self] in self?.startRegionCapture() }
        hotkeys.onScroll     = { [weak self] in self?.startScrollCapture() }
        hotkeys.setup()
    }

    func captureFullScreen() {
        guard !isCapturing else { return }
        showPermissionButton = false
        isCapturing = true
        statusMessage = "截图中…"
        Task {
            do {
                let image = try await screenshotService.captureFullScreen()
                let url = try fileSaveService.save(image: image)
                clipboardService.copy(image: image)
                statusMessage = "已保存：\(url.lastPathComponent)"
            } catch CaptureError.permissionDenied {
                AppDelegate.shared?.openPanel()
                showScreenRecordingPermissionError()
            } catch {
                AppDelegate.shared?.openPanel()
                statusMessage = "截图失败"
            }
            isCapturing = false
        }
    }

    func startRegionCapture() {
        guard !isCapturing else { return }
        showPermissionButton = false
        isCapturing = true
        statusMessage = "准备中…"
        Task {
            do {
                let baseImage = try await screenshotService.captureFullScreen()
                statusMessage = "拖拽选择区域"
                OverlayWindowController.shared.show(baseImage: baseImage) { [weak self] rect in
                    guard let self else { return }
                    Task { @MainActor in
                        await self.handleRegionSelected(rect, baseImage: baseImage)
                    }
                }
            } catch CaptureError.permissionDenied {
                AppDelegate.shared?.openPanel()
                showScreenRecordingPermissionError()
                isCapturing = false
            } catch {
                AppDelegate.shared?.openPanel()
                statusMessage = "截图失败"
                isCapturing = false
            }
        }
    }

    private func handleRegionSelected(_ rect: CGRect?, baseImage: NSImage) async {
        guard let rect else {
            statusMessage = "已取消"
            isCapturing = false
            return
        }
        do {
            let image = try regionCaptureService.captureRegion(rect: rect, from: baseImage)
            let url = try fileSaveService.save(image: image)
            clipboardService.copy(image: image)
            statusMessage = "已保存：\(url.lastPathComponent)"
        } catch {
            statusMessage = "截图失败"
        }
        isCapturing = false
    }

    func requestAccessibilityPermission() {
        statusMessage = "自动滚动需要辅助功能权限"
        pendingPermissionURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        showPermissionButton = true
    }

    func startScrollCapture() {
        guard !isCapturing else { return }
        showPermissionButton = false

        if !AXIsProcessTrusted() {
            AppDelegate.shared?.openPanel()
            requestAccessibilityPermission()
            return
        }

        isCapturing = true
        statusMessage = "准备中…"
        Task {
            do {
                let baseImage = try await screenshotService.captureFullScreen()
                let targetApp = NSWorkspace.shared.frontmostApplication
                statusMessage = "拖拽选择截图区域"
                OverlayWindowController.shared.show(baseImage: baseImage) { [weak self] rect in
                    guard let self else { return }
                    Task { @MainActor in
                        guard let rect else {
                            self.statusMessage = "已取消"
                            self.isCapturing = false
                            return
                        }
                        ScrollCaptureController.shared.beginCapturing(
                            rect: rect, baseImage: baseImage, targetApp: targetApp
                        ) { [weak self] image in
                            guard let self else { return }
                            Task { @MainActor in
                                if let image {
                                    do {
                                        let url = try self.fileSaveService.save(image: image)
                                        self.clipboardService.copy(image: image)
                                        self.statusMessage = "已保存：\(url.lastPathComponent)"
                                    } catch {
                                        self.statusMessage = "保存失败"
                                    }
                                } else {
                                    self.statusMessage = "已取消"
                                }
                                self.isCapturing = false
                            }
                        }
                    }
                }
            } catch CaptureError.permissionDenied {
                AppDelegate.shared?.openPanel()
                showScreenRecordingPermissionError()
                isCapturing = false
            } catch {
                AppDelegate.shared?.openPanel()
                statusMessage = "截图失败"
                isCapturing = false
            }
        }
    }

    func openSystemSettings() {
        if let url = URL(string: pendingPermissionURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func showScreenRecordingPermissionError() {
        if CGPreflightScreenCaptureAccess() {
            // 权限已在系统设置中授权，但 ScreenCaptureKit 需要重启才能识别
            statusMessage = "权限已开启，请重启 App 以生效"
            showPermissionButton = false
        } else {
            // 尚未授权
            statusMessage = "需要开启屏幕录制权限"
            pendingPermissionURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            showPermissionButton = true
        }
    }
}

// MARK: - KeyCaptureView

struct KeyCaptureView: NSViewRepresentable {
    var isRecording: Bool
    var onKey: (NSEvent) -> Void
    var onResign: () -> Void

    func makeNSView(context: Context) -> RecorderNSView { RecorderNSView() }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.onKey = onKey
        nsView.onResign = onResign
        if isRecording {
            DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
        } else if nsView.window?.firstResponder === nsView {
            nsView.window?.makeFirstResponder(nil)
        }
    }
}

class RecorderNSView: NSView {
    var onKey: ((NSEvent) -> Void)?
    var onResign: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { onKey?(event) }
    override func resignFirstResponder() -> Bool {
        let r = super.resignFirstResponder()
        if r { onResign?() }
        return r
    }
}

// MARK: - ShortcutRow

struct ShortcutRow: View {
    let label: String
    let config: HotkeyConfig?
    let onSet: (HotkeyConfig?) -> Void
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.lInkSubtle)
                .frame(width: 56, alignment: .leading)

            Spacer().frame(width: 8)

            // Key badge
            Button { isRecording.toggle() } label: {
                Text(isRecording ? "请按键…" : (config?.displayString ?? "未设置"))
                    .font(.system(size: 11, weight: .medium).monospaced())
                    .foregroundColor(
                        isRecording ? .lAccent
                            : (config != nil ? .lInkMuted : .lInkTertiary)
                    )
                    .padding(.horizontal, 8)
                    .frame(minWidth: 72, minHeight: 24, maxHeight: 24)
                    .background(Color.lSurface3)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(
                                isRecording ? Color.lAccent : Color.lHairline,
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)

            KeyCaptureView(
                isRecording: isRecording,
                onKey: { event in
                    if event.keyCode == 53 { isRecording = false; return }
                    if let cfg = HotkeyConfig.from(event: event) {
                        onSet(cfg); isRecording = false
                    }
                },
                onResign: { isRecording = false }
            )
            .frame(width: 0, height: 0)

            Spacer()

            if config != nil, !isRecording {
                Button("清除") { onSet(nil) }
                    .buttonStyle(GhostButtonStyle())
            }
        }
    }
}

// MARK: - MainView

struct MainView: View {
    @StateObject private var viewModel = MainViewModel()
    @ObservedObject private var hotkeys = HotkeyService.shared

    private func dismissThenCapture(_ action: @escaping () -> Void) {
        AppDelegate.shared?.closePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { action() }
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Actions ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 14) {

                Text("截图工具")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.lInkSubtle)
                    .tracking(0.6)
                    .textCase(.uppercase)

                VStack(spacing: 6) {
                    Button("全屏截图") { dismissThenCapture { viewModel.captureFullScreen() } }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(viewModel.isCapturing)
                    Button("区域截图") { dismissThenCapture { viewModel.startRegionCapture() } }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(viewModel.isCapturing)
                    Button("滚动截图") {
                        guard AXIsProcessTrusted() else {
                            viewModel.requestAccessibilityPermission()
                            return
                        }
                        dismissThenCapture { viewModel.startScrollCapture() }
                    }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(viewModel.isCapturing)
                }

                HStack(spacing: 6) {
                    if viewModel.isCapturing {
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(width: 12, height: 12)
                    }
                    Text(viewModel.statusMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.lInkSubtle)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if viewModel.showPermissionButton {
                    Button("打开系统设置") { viewModel.openSystemSettings() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(16)

            Rectangle().fill(Color.lHairline).frame(height: 1)

            // ── Shortcuts ────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                Text("快捷键")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.lInkSubtle)
                    .tracking(0.6)
                    .textCase(.uppercase)

                ShortcutRow(label: "全屏截图", config: hotkeys.fullScreenConfig) {
                    HotkeyService.shared.setFullScreen($0)
                }
                ShortcutRow(label: "区域截图", config: hotkeys.regionConfig) {
                    HotkeyService.shared.setRegion($0)
                }
                ShortcutRow(label: "滚动截图", config: hotkeys.scrollConfig) {
                    HotkeyService.shared.setScroll($0)
                }
            }
            .padding(16)

            Rectangle().fill(Color.lHairline).frame(height: 1)

            // ── Footer ───────────────────────────────────────────
            HStack {
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
                    .buttonStyle(GhostButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 280)
        .background(Color.lSurface1)
        .preferredColorScheme(.dark)
        .onAppear { viewModel.setupHotkeys() }
    }
}
