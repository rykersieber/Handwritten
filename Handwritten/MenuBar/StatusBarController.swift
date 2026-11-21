import AppKit
import Combine

/// The menu bar icon, its status text, its menu, and the dummy icon used by mask mode.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var dummy: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private let state = AppState.shared

    override init() {
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.imagePosition = .imageLeading
        refresh()
        state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in DispatchQueue.main.async { self?.refresh() } }
            .store(in: &cancellables)
        SettingsStore.didChange.receive(on: DispatchQueue.main)
            .sink { [weak self] key in if key.hasPrefix("app.") || key.hasPrefix("gen.") || key == "*" { self?.refresh() } }
            .store(in: &cancellables)
    }

    // MARK: Icon + title

    func refresh() {
        guard let button = item.button else { return }
        let s = SettingsStore.shared
        let symbol = s.str(K.menuIcon)
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "Handwritten")
            ?? NSImage(systemSymbolName: "pencil.line", accessibilityDescription: "Handwritten")!
        var color: NSColor?
        var title = ""
        switch state.runState {
        case .idle:
            color = nil
        case .countdown(let n):
            color = .systemOrange
            if s.bool(K.showCountdownInMenu) { title = " \(n)" }
        case .typing, .verifying:
            color = s.bool(K.colorIconWhenTyping) ? ThemeStore.shared.nsAccent : nil
            if s.bool(K.showPercent) { title = " \(state.percentText)" }
        case .paused:
            color = .systemYellow
            if s.bool(K.showPercent) { title = " ⏸ \(state.percentText)" }
        }
        if let color {
            let cfg = NSImage.SymbolConfiguration(paletteColors: [color])
            let img = base.withSymbolConfiguration(cfg) ?? base
            img.isTemplate = false
            button.image = img
        } else {
            base.isTemplate = true
            button.image = base
        }
        button.title = title
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        button.toolTip = statusLine
    }

    private var statusLine: String {
        switch state.runState {
        case .idle:
            let n = ClipboardManager.shared.currentText.count
            return state.lastMessage.isEmpty ? "Ready — \(n) characters on the clipboard" : state.lastMessage
        case .countdown(let n): return "Starting in \(n)…"
        case .typing: return "Typing \(state.percentText) — \(TimeFormat.short(state.secondsRemaining)) left"
        case .paused: return "Paused at \(state.percentText) — \(state.lastMessage)"
        case .verifying: return "Checking the text…"
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = SettingsStore.shared
        let rs = state.runState

        let header = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let startTitle = rs == .paused ? "Resume" : "Start Typing"
        menu.addItem(makeItem(startTitle, symbol: "play.fill", hotkey: K.hkStart, enabled: rs == .idle || rs == .paused) {
            if AppState.shared.runState == .paused { TypingController.shared.resume() } else { TypingController.shared.start() }
        })
        menu.addItem(makeItem("Pause", symbol: "pause.fill", hotkey: K.hkPause, enabled: rs == .typing) {
            TypingController.shared.pause(reason: "Paused")
        })
        menu.addItem(makeItem("Stop", symbol: "stop.fill", hotkey: K.hkStop, enabled: rs.isActive) {
            TypingController.shared.stop()
        })

        if s.bool(K.historyInMenu) {
            menu.addItem(.separator())
            let h = NSMenuItem(title: "Clipboard History", action: nil, keyEquivalent: "")
            h.isEnabled = false
            menu.addItem(h)
            let items = ClipboardManager.shared.items
            if items.isEmpty {
                let e = NSMenuItem(title: "Nothing copied yet", action: nil, keyEquivalent: "")
                e.isEnabled = false
                menu.addItem(e)
            }
            let current = ClipboardManager.shared.currentText
            let len = s.int(K.menuPreviewLength)
            for it in items {
                let mi = makeItem(it.preview(len), symbol: it.pinned ? "pin.fill" : nil, enabled: true) {
                    ClipboardManager.shared.select(it)
                }
                mi.state = it.text == current ? .on : .off
                mi.toolTip = String(it.text.prefix(400))
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())
        let presetMenu = NSMenu()
        let custom = makeItem("Custom (my settings)", enabled: true) { SettingsStore.shared.useCustom() }
        custom.state = s.isCustom || PresetStore.shared.preset(named: s.activePresetName) == nil ? .on : .off
        presetMenu.addItem(custom)
        presetMenu.addItem(makeItem("Save Current Settings as Preset…", enabled: true) {
            AppDelegate.shared?.showSettings(tab: .presets)
        })
        presetMenu.addItem(.separator())
        for p in PresetStore.shared.all {
            let mi = makeItem(p.name, enabled: true) {
                SettingsStore.shared.apply(preset: p)
            }
            mi.state = s.activePresetName == p.name ? .on : .off
            mi.toolTip = p.detail
            presetMenu.addItem(mi)
        }
        let presetItem = NSMenuItem(title: "Preset: \(s.activePresetName)", action: nil, keyEquivalent: "")
        presetItem.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil)
        presetItem.submenu = presetMenu
        menu.addItem(presetItem)

        menu.addItem(.separator())
        menu.addItem(makeItem("Open Control Panel", symbol: "macwindow", hotkey: K.hkPanel, enabled: true) {
            AppDelegate.shared?.showControlPanel()
        })
        menu.addItem(makeItem("Settings…", symbol: "gearshape", enabled: true) { AppDelegate.shared?.showSettings() })
        menu.addItem(makeItem("Personalize (learn my typing)…", symbol: "person.crop.circle.badge.checkmark", enabled: true) {
            AppDelegate.shared?.showPersonalize()
        })
        menu.addItem(makeItem("Hide Everything (Mask)", symbol: "eye.slash", hotkey: K.hkMask, enabled: true) {
            AppDelegate.shared?.setMasked(true)
        })
        if !PermissionsManager.shared.allGranted {
            menu.addItem(makeItem("Permissions Needed…", symbol: "exclamationmark.triangle", enabled: true) {
                AppDelegate.shared?.showOnboarding()
            })
        }
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Handwritten", enabled: true) { NSApp.terminate(nil) })
    }

    private func makeItem(_ title: String, symbol: String? = nil, hotkey: String? = nil, enabled: Bool,
                          action: @escaping () -> Void) -> NSMenuItem {
        let mi = ClosureMenuItem(title: title, handler: action)
        mi.isEnabled = enabled
        if let symbol { mi.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        if let hotkey, let combo = HotkeyCombo(storage: SettingsStore.shared.str(hotkey)) {
            mi.title = "\(title)    \(combo.display)"
        }
        return mi
    }

    // MARK: Mask

    func applyMask(_ masked: Bool) {
        item.isVisible = !masked
        dummy.map { NSStatusBar.system.removeStatusItem($0) }
        dummy = nil
        guard masked, SettingsStore.shared.bool(K.maskDummyIcon) else { return }
        let d = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let symbol: String
        switch SettingsStore.shared.str(K.maskDummyStyle) {
        case "wifi": symbol = "wifi"
        case "battery": symbol = "battery.75percent"
        case "cloud": symbol = "icloud"
        case "clock": symbol = "clock"
        case "gear": symbol = "gearshape"
        default: symbol = "circle.fill"
        }
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        img?.isTemplate = true
        if symbol == "circle.fill" { img?.size = NSSize(width: 8, height: 8) }
        d.button?.image = img
        d.button?.target = self
        d.button?.action = #selector(dummyClicked)
        dummy = d
    }

    @objc private func dummyClicked() {
        if SettingsStore.shared.bool(K.maskRequireOption) && !NSEvent.modifierFlags.contains(.option) { return }
        AppDelegate.shared?.setMasked(false)
    }
}

/// NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { handler() }
}
