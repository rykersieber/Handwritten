import AppKit
import SwiftUI
import Combine
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private var statusBar: StatusBarController!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        _ = ThemeStore.shared
        WordData.shared.installAndLoad()
        if ProcessInfo.processInfo.environment["HW_SELFTEST"] != nil {
            exit(SelfTest.run())
        }
        ClipboardManager.shared.start()
        PermissionsManager.shared.startPolling()
        statusBar = StatusBarController()
        _ = TypingController.shared
        InputMonitor.shared.start()

        HotkeyManager.shared.onAction = { [weak self] action in self?.handleHotkey(action) }
        HotkeyManager.shared.start()

        // React to settings that affect the app shell.
        SettingsStore.didChange.receive(on: DispatchQueue.main).sink { [weak self] key in
            guard let self else { return }
            if key == K.launchAtLogin || key == "*" { self.syncLaunchAtLogin() }
            if key == K.showDockIcon || key == "*" { self.updateActivationPolicy() }
        }.store(in: &cancellables)

        // When permissions are granted later, (re)start the input monitor.
        PermissionsManager.shared.$inputMonitoring.removeDuplicates().sink { granted in
            if granted { InputMonitor.shared.restartIfNeeded() }
        }.store(in: &cancellables)

        let s = SettingsStore.shared
        if !PermissionsManager.shared.allGranted {
            showOnboarding()
        } else if s.bool(K.openPanelOnLaunch) && !s.bool(K.maskOnLaunch) {
            showControlPanel()
        }
        if s.bool(K.maskOnLaunch) { setMasked(true) }
        updateActivationPolicy()

        // Debug: open windows on launch, e.g. HW_SHOW=settings:typos or HW_SHOW=panel
        if let show = ProcessInfo.processInfo.environment["HW_SHOW"] {
            let parts = show.split(separator: ":").map(String.init)
            WindowManager.shared.close(.onboarding)
            if parts[0] == "panel" { showControlPanel() }
            if parts[0] == "settings" { showSettings(tab: parts.count > 1 ? SettingTab(rawValue: parts[1]) : nil) }
            if parts[0] == "onboarding" { showOnboarding() }
            if parts[0] == "personalize" { showPersonalize() }
        }

        if let dir = ProcessInfo.processInfo.environment["HW_RENDER"] {
            WindowManager.shared.close(.onboarding)
            RenderSnapshots.run(dir: dir)
        }

        if let dir = ProcessInfo.processInfo.environment["HW_E2E"] {
            WindowManager.shared.close(.onboarding)
            E2ETest.run(outputDir: dir)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        TypingController.shared.stop()
        ClipboardManager.shared.handleQuit()
        SettingsStore.shared.saveNow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AppState.shared.isMasked { return false }
        showControlPanel()
        return true
    }

    // MARK: Hotkeys

    private func handleHotkey(_ action: HotkeyAction) {
        let tc = TypingController.shared
        let state = AppState.shared.runState
        switch action {
        case .start:
            if state == .idle { tc.start() } else if state == .paused { tc.resume() }
        case .pause:
            if state == .typing { tc.pause(reason: "Paused") } else if state == .paused { tc.resume() }
        case .stop:
            if state.isActive { tc.stop() }
        case .mask:
            setMasked(!AppState.shared.isMasked)
        case .panel:
            if AppState.shared.isMasked { setMasked(false) }
            showControlPanel()
        }
    }

    // MARK: Windows

    func showOnboarding() {
        WindowManager.shared.show(.onboarding, title: "Handwritten Setup", size: NSSize(width: 480, height: 420)) {
            OnboardingView(onDone: { [weak self] in
                WindowManager.shared.close(.onboarding)
                self?.showControlPanel()
            }).themed()
        }
    }

    func showControlPanel() {
        WindowManager.shared.show(.controlPanel, title: "Handwritten", size: NSSize(width: 400, height: 640), resizable: true) {
            ControlPanelView().themed()
        }
    }

    func showSettings(tab: SettingTab? = nil) {
        if let tab { SettingsNavigation.shared.selectedTab = tab }
        WindowManager.shared.show(.settings, title: "Handwritten Settings", size: NSSize(width: 860, height: 640),
                                  resizable: true, floating: false) {
            SettingsView().themed()
        }
    }

    func showPersonalize() {
        WindowManager.shared.show(.personalize, title: "Personalize", size: NSSize(width: 720, height: 640),
                                  resizable: true, floating: false) {
            PersonalizeView().themed()
        }
    }

    func showHistoryEditor(_ item: ClipboardItem) {
        WindowManager.shared.destroy(.historyEditor)
        WindowManager.shared.show(.historyEditor, title: "Edit Clipboard Item", size: NSSize(width: 560, height: 420), resizable: true) {
            HistoryEditorView(item: item).themed()
        }
    }

    func showDataEditor(_ file: WordData.File) {
        WindowManager.shared.destroy(.dataEditor)
        WindowManager.shared.show(.dataEditor, title: file.title, size: NSSize(width: 620, height: 560), resizable: true, floating: false) {
            DataEditorView(file: file).themed()
        }
    }

    // MARK: Mask

    func setMasked(_ masked: Bool) {
        let state = AppState.shared
        guard state.isMasked != masked else { return }
        if masked {
            if SettingsStore.shared.bool(K.maskStopsTyping) && state.runState.isActive { TypingController.shared.stop() }
            WindowManager.shared.hideAllForMask()
            state.isMasked = true
            statusBar.applyMask(true)
        } else {
            state.isMasked = false
            statusBar.applyMask(false)
            WindowManager.shared.restoreAfterMask()
            if state.runState.isActive && SettingsStore.shared.bool(K.showHUD) {
                WindowManager.shared.showHUD(.hud, size: NSSize(width: 300, height: 74)) { ProgressHUDView().themed() }
            }
        }
        updateActivationPolicy()
    }

    // MARK: System

    func updateActivationPolicy() {
        let wantDock = SettingsStore.shared.bool(K.showDockIcon) && !AppState.shared.isMasked
        let policy: NSApplication.ActivationPolicy = wantDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    private func syncLaunchAtLogin() {
        let want = SettingsStore.shared.bool(K.launchAtLogin)
        let service = SMAppService.mainApp
        do {
            if want && service.status != .enabled { try service.register() }
            if !want && service.status == .enabled { try service.unregister() }
        } catch {
            AppState.shared.lastMessage = "Couldn't change launch at login: \(error.localizedDescription)"
        }
    }
}
