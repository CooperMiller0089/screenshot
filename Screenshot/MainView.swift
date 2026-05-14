import AppKit
import Combine
import SwiftUI

// MARK: - Claude palette

private extension Color {
    static let cBg         = Color(red: 250/255, green: 249/255, blue: 246/255)  // #FAF9F6
    static let cSurface    = Color(red: 244/255, green: 241/255, blue: 236/255)  // #F4F1EC
    static let cBorder     = Color(red: 232/255, green: 227/255, blue: 218/255)  // #E8E3DA
    static let cInk        = Color(red: 25/255,  green: 25/255,  blue: 25/255)   // #191919
    static let cInkMid     = Color(red: 107/255, green: 101/255, blue: 96/255)   // #6B6560
    static let cInkFaint   = Color(red: 158/255, green: 151/255, blue: 144/255)  // #9E9790
    static let cAccent     = Color(red: 217/255, green: 119/255, blue: 87/255)   // #D97757
    static let cAccentDeep = Color(red: 201/255, green: 98/255,  blue: 63/255)   // #C9623F
}

// MARK: - Button styles

private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(configuration.isPressed ? Color.cAccentDeep : Color.cAccent)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(configuration.isPressed ? .cInk : .cInkMid)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(configuration.isPressed ? Color.cSurface : Color.cBg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.cBorder, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
    }
}

private struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11))
            .foregroundColor(configuration.isPressed ? .cInkMid : .cInkFaint)
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
            statusMessage = "权限已开启，请重启 App 以生效"
            showPermissionButton = false
        } else {
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
                .foregroundColor(.cInkMid)
                .frame(width: 60, alignment: .leading)

            Spacer().frame(width: 8)

            Button { isRecording.toggle() } label: {
                Text(isRecording ? "请按键…" : (config?.displayString ?? "未设置"))
                    .font(.system(size: 11, weight: .medium).monospaced())
                    .foregroundColor(
                        isRecording ? .cAccent
                            : (config != nil ? .cInk : .cInkFaint)
                    )
                    .padding(.horizontal, 8)
                    .frame(minWidth: 72, minHeight: 24, maxHeight: 24)
                    .background(Color.cSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(
                                isRecording ? Color.cAccent : Color.cBorder,
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

            // ── Header ───────────────────────────────────────────
            HStack(alignment: .center) {
                Text("截图")
                    .font(.custom("Georgia", size: 17).weight(.semibold))
                    .foregroundColor(.cInk)
                Spacer()
                if viewModel.isCapturing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                        .tint(Color.cAccent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 18)

            // ── Actions ──────────────────────────────────────────
            VStack(spacing: 8) {
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
            .padding(.horizontal, 20)

            // ── Status ───────────────────────────────────────────
            Text(viewModel.statusMessage)
                .font(.system(size: 11))
                .foregroundColor(.cInkFaint)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            if viewModel.showPermissionButton {
                Button("打开系统设置") { viewModel.openSystemSettings() }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            // ── Divider ──────────────────────────────────────────
            Rectangle()
                .fill(Color.cBorder)
                .frame(height: 1)
                .padding(.top, 18)

            // ── Shortcuts ────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                Text("快捷键")
                    .font(.custom("Georgia", size: 11).italic())
                    .foregroundColor(.cInkFaint)
                    .padding(.bottom, 2)

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
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            // ── Footer ───────────────────────────────────────────
            Rectangle()
                .fill(Color.cBorder)
                .frame(height: 1)

            HStack {
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
                    .buttonStyle(GhostButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(width: 280)
        .background(Color.cBg)
        .preferredColorScheme(.light)
        .onAppear { viewModel.setupHotkeys() }
    }
}
