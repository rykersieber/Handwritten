import AppKit
import Carbon.HIToolbox
import Combine

/// A key + modifiers combo, stored as "keyCode:carbonModifiers".
struct HotkeyCombo: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon modifier flags (cmdKey, optionKey, controlKey, shiftKey)

    static let ctrlOptCmd = UInt32(controlKey | optionKey | cmdKey)
    static let defaultStart = HotkeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: ctrlOptCmd)
    static let defaultPause = HotkeyCombo(keyCode: UInt32(kVK_ANSI_P), modifiers: ctrlOptCmd)
    static let defaultStop = HotkeyCombo(keyCode: UInt32(kVK_ANSI_X), modifiers: ctrlOptCmd)
    static let defaultMask = HotkeyCombo(keyCode: UInt32(kVK_ANSI_H), modifiers: ctrlOptCmd)
    static let defaultPanel = HotkeyCombo(keyCode: UInt32(kVK_ANSI_O), modifiers: ctrlOptCmd)

    var storage: String { "\(keyCode):\(modifiers)" }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(storage: String) {
        let parts = storage.split(separator: ":")
        guard parts.count == 2, let k = UInt32(parts[0]), let m = UInt32(parts[1]) else { return nil }
        keyCode = k; modifiers = m
    }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        modifiers = HotkeyCombo.carbon(from: event.modifierFlags)
    }

    static func carbon(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    /// Matches a CGEvent's flags and keycode.
    func matches(keyCode k: Int64, flags: CGEventFlags) -> Bool {
        guard UInt32(k) == keyCode else { return false }
        var m: UInt32 = 0
        if flags.contains(.maskCommand) { m |= UInt32(cmdKey) }
        if flags.contains(.maskAlternate) { m |= UInt32(optionKey) }
        if flags.contains(.maskControl) { m |= UInt32(controlKey) }
        if flags.contains(.maskShift) { m |= UInt32(shiftKey) }
        return m == modifiers
    }

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + HotkeyCombo.keyName(keyCode)
    }

    static func keyName(_ code: UInt32) -> String {
        let special: [Int: String] = [
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ForwardDelete: "⌦",
        ]
        if let s = special[Int(code)] { return s }
        if let c = KeyLayout.character(forKeyCode: UInt16(code)) { return String(c).uppercased() }
        return "Key \(code)"
    }
}

enum HotkeyAction: UInt32, CaseIterable {
    case start = 1, pause, stop, mask, panel

    var settingKey: String {
        switch self {
        case .start: return K.hkStart
        case .pause: return K.hkPause
        case .stop: return K.hkStop
        case .mask: return K.hkMask
        case .panel: return K.hkPanel
        }
    }
}

/// Registers global hotkeys with Carbon (no Accessibility needed for this part).
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var refs: [HotkeyAction: EventHotKeyRef] = [:]
    private var handlerInstalled = false
    private var cancellable: AnyCancellable?
    private(set) var active: [HotkeyAction: HotkeyCombo] = [:]
    /// Set while the recorder is capturing, so hotkeys don't fire.
    var suspended = false {
        didSet { suspended ? unregisterAll() : registerAll() }
    }

    var onAction: ((HotkeyAction) -> Void)?

    func start() {
        installHandler()
        registerAll()
        cancellable = SettingsStore.didChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] key in
                if key == "*" || key.hasPrefix("hotkey.") { self?.registerAll() }
            }
    }

    /// True if a key event matches one of our active hotkeys (used to ignore it for auto-pause).
    nonisolated func isHotkey(keyCode: Int64, flags: CGEventFlags) -> Bool {
        let combos = MainActor.assumeIsolated { Array(self.active.values) }
        return combos.contains { $0.matches(keyCode: keyCode, flags: flags) }
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if let action = HotkeyAction(rawValue: hkID.id) {
                DispatchQueue.main.async { HotkeyManager.shared.onAction?(action) }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    func unregisterAll() {
        for (_, ref) in refs { UnregisterEventHotKey(ref) }
        refs = [:]
        active = [:]
    }

    func registerAll() {
        unregisterAll()
        let s = SettingsStore.shared
        guard s.bool(K.hkEnabled), !suspended else { return }
        for action in HotkeyAction.allCases {
            if action == .pause && !s.bool(K.hkPauseEnabled) { continue }
            guard let combo = HotkeyCombo(storage: s.str(action.settingKey)) else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x48574E44), id: action.rawValue) // 'HWND'
            let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs[action] = ref
                active[action] = combo
            }
        }
    }
}
