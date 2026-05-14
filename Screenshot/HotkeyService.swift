import Carbon
import AppKit
import Combine

// MARK: - HotkeyConfig

struct HotkeyConfig: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32  // Carbon modifier flags

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        s += keyCodeToChar(keyCode)
        return s
    }

    // Build from NSEvent; requires at least one modifier key
    static func from(event: NSEvent) -> HotkeyConfig? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command) || mods.contains(.option) || mods.contains(.control) else {
            return nil   
        }
        var carbon: UInt32 = 0
        if mods.contains(.command) { carbon |= UInt32(cmdKey) }
        if mods.contains(.option)  { carbon |= UInt32(optionKey) }
        if mods.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if mods.contains(.control) { carbon |= UInt32(controlKey) }
        return HotkeyConfig(keyCode: UInt32(event.keyCode), modifiers: carbon)
    }
}

private func keyCodeToChar(_ keyCode: UInt32) -> String {
    let map: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P",
        37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
        22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
        97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12",
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫",
        126: "↑", 125: "↓", 123: "←", 124: "→",
    ]
    return map[keyCode] ?? "(\(keyCode))"
}

// MARK: - HotkeyService

@MainActor
class HotkeyService: ObservableObject {
    static let shared = HotkeyService()

    @Published private(set) var fullScreenConfig: HotkeyConfig?
    @Published private(set) var regionConfig: HotkeyConfig?
    @Published private(set) var scrollConfig: HotkeyConfig?

    var onFullScreen: (() -> Void)?
    var onRegion: (() -> Void)?
    var onScroll: (() -> Void)?

    private var fullScreenRef: EventHotKeyRef?
    private var regionRef: EventHotKeyRef?
    private var scrollRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private static let sig = OSType(0x5343484B)  // "SCHK"

    init() { loadConfigs() }

    func setup() {
        installEventHandler()
        if let c = fullScreenConfig { register(c, id: 1, ref: &fullScreenRef) }
        if let c = regionConfig     { register(c, id: 2, ref: &regionRef) }
        if let c = scrollConfig     { register(c, id: 3, ref: &scrollRef) }
    }

    func setFullScreen(_ config: HotkeyConfig?) {
        unregister(&fullScreenRef)
        fullScreenConfig = config
        if let c = config { register(c, id: 1, ref: &fullScreenRef) }
        saveConfigs()
    }

    func setRegion(_ config: HotkeyConfig?) {
        unregister(&regionRef)
        regionConfig = config
        if let c = config { register(c, id: 2, ref: &regionRef) }
        saveConfigs()
    }

    func setScroll(_ config: HotkeyConfig?) {
        unregister(&scrollRef)
        scrollConfig = config
        if let c = config { register(c, id: 3, ref: &scrollRef) }
        saveConfigs()
    }

    // Called from Carbon callback via Task { @MainActor in }
    func fire(id: UInt32) {
        switch id {
        case 1: onFullScreen?()
        case 2: onRegion?()
        case 3: onScroll?()
        default: break
        }
    }

    // MARK: - Private

    private func installEventHandler() {
        guard eventHandlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID
                )
                let firedID = hkID.id
                Task { @MainActor in
                    HotkeyService.shared.fire(id: firedID)
                }
                return noErr
            },
            1, &spec, nil, &eventHandlerRef
        )
    }

    private func register(_ config: HotkeyConfig, id: UInt32, ref: inout EventHotKeyRef?) {
        let hkID = EventHotKeyID(signature: HotkeyService.sig, id: id)
        RegisterEventHotKey(
            config.keyCode, config.modifiers, hkID,
            GetApplicationEventTarget(), 0, &ref
        )
    }

    private func unregister(_ ref: inout EventHotKeyRef?) {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
    }

    private func saveConfigs() {
        let enc = JSONEncoder()
        UserDefaults.standard.set(try? enc.encode(fullScreenConfig), forKey: "hk_fullscreen")
        UserDefaults.standard.set(try? enc.encode(regionConfig),     forKey: "hk_region")
        UserDefaults.standard.set(try? enc.encode(scrollConfig),     forKey: "hk_scroll")
    }

    private func loadConfigs() {
        let dec = JSONDecoder()
        if let d = UserDefaults.standard.data(forKey: "hk_fullscreen") {
            fullScreenConfig = try? dec.decode(HotkeyConfig.self, from: d)
        }
        if let d = UserDefaults.standard.data(forKey: "hk_region") {
            regionConfig = try? dec.decode(HotkeyConfig.self, from: d)
        }
        if let d = UserDefaults.standard.data(forKey: "hk_scroll") {
            scrollConfig = try? dec.decode(HotkeyConfig.self, from: d)
        }
    }
}
