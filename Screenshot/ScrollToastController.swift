import AppKit

// Linear palette (NSColor)
private enum LC {
    static let surface2  = NSColor(srgbRed: 20/255, green: 21/255, blue: 22/255, alpha: 0.96)
    static let hairline  = NSColor(srgbRed: 35/255, green: 37/255, blue: 42/255, alpha: 1)
    static let ink       = NSColor(srgbRed: 247/255, green: 248/255, blue: 248/255, alpha: 1)
}

@MainActor
class ScrollToastController {
    static let shared = ScrollToastController()

    private var window: NSPanel?
    private var label: NSTextField?
    private var dismissTask: Task<Void, Never>?

    // MARK: - Public API

    func show(_ message: String, autoDismiss: Bool = false, autoDismissDelay: Int = 1000, in rect: CGRect? = nil) {
        dismissTask?.cancel()
        dismissTask = nil

        buildOrUpdate(message: message, in: rect)

        window?.alphaValue = 0
        window?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window?.animator().alphaValue = 1
        }

        if autoDismiss {
            dismissTask = Task {
                try? await Task.sleep(for: .milliseconds(autoDismissDelay))
                guard !Task.isCancelled else { return }
                self.hide()
            }
        }
    }

    func hideImmediately() {
        dismissTask?.cancel()
        dismissTask = nil
        window?.orderOut(nil)
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        guard let win = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            win.animator().alphaValue = 0
        }, completionHandler: {
            win.orderOut(nil)
        })
    }

    // MARK: - Private

    private func buildOrUpdate(message: String, in captureRect: CGRect? = nil) {
        let hPad: CGFloat = 16
        let vPad: CGFloat = 10
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]

        let textSize = (message as NSString).size(withAttributes: attrs)
        let toastW = ceil(textSize.width) + hPad * 2
        let toastH = ceil(textSize.height) + vPad * 2

        guard let screen = NSScreen.main else { return }
        let x: CGFloat
        let y: CGFloat
        if let r = captureRect {
            x = r.midX - toastW / 2
            y = r.midY - toastH / 2
        } else {
            x = screen.frame.minX + (screen.frame.width - toastW) / 2
            y = screen.frame.minY + screen.frame.height * 0.54
        }

        if let win = window {
            win.setFrame(NSRect(x: x, y: y, width: toastW, height: toastH), display: false)
            label?.stringValue = message
            label?.frame = NSRect(x: 0, y: vPad, width: toastW, height: ceil(textSize.height))
            styleContainer(win.contentView!, size: NSSize(width: toastW, height: toastH))
            return
        }

        // Build window fresh
        let win = NSPanel(
            contentRect: NSRect(x: x, y: y, width: toastW, height: toastH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.level             = .floating
        win.isOpaque          = false
        win.backgroundColor   = .clear
        win.hasShadow         = true
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.sharingType       = .none

        let container = NSView(frame: NSRect(origin: .zero,
                                             size: NSSize(width: toastW, height: toastH)))
        styleContainer(container, size: NSSize(width: toastW, height: toastH))

        let tf = NSTextField(labelWithString: message)
        tf.font      = font
        tf.textColor = LC.ink
        tf.alignment = .center
        tf.frame     = NSRect(x: 0, y: vPad, width: toastW, height: ceil(textSize.height))
        container.addSubview(tf)

        win.contentView = container
        self.window = win
        self.label  = tf
    }

    private func styleContainer(_ view: NSView, size: NSSize) {
        view.wantsLayer = true
        view.layer?.backgroundColor = LC.surface2.cgColor
        view.layer?.cornerRadius    = 8
        view.layer?.masksToBounds   = true
        view.layer?.borderColor     = LC.hairline.cgColor
        view.layer?.borderWidth     = 1
    }
}
