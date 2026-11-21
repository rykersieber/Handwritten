import AppKit
import CoreGraphics

/// Watches the user's own keyboard and mouse (never our synthetic events) to
/// stop on Escape and auto-pause on clicks, key presses, and app switches.
@MainActor
final class InputMonitor {
    static let shared = InputMonitor()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitors: [Any] = []
    private var workspaceObserver: NSObjectProtocol?

    /// Called on the main thread.
    var onEscape: (() -> Void)?
    var onUserInterrupt: ((String) -> Void)?
    var onAppSwitch: ((pid_t) -> Void)?

    var usingEventTap: Bool { tap != nil }

    func start() {
        stop()
        installTap()
        if tap == nil { installFallbackMonitors() }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { self?.onAppSwitch?(pid) }
        }
    }

    func restartIfNeeded() {
        if tap == nil && CGPreflightListenEventAccess() { start() }
    }

    func stop() {
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        tap = nil
        runLoopSource = nil
        for m in globalMonitors { NSEvent.removeMonitor(m) }
        globalMonitors = []
        if let o = workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        workspaceObserver = nil
    }

    private func installTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                DispatchQueue.main.async { InputMonitor.shared.reenable() }
                return Unmanaged.passUnretained(event)
            }
            if event.getIntegerValueField(.eventSourceUserData) == KeySender.marker {
                return Unmanaged.passUnretained(event)
            }
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            let loc = event.location
            DispatchQueue.main.async {
                InputMonitor.shared.handle(type: type, keyCode: keyCode, flags: flags, location: loc)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                        options: .listenOnly, eventsOfInterest: mask,
                                        callback: callback, userInfo: nil) else { return }
        tap = t
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    private func reenable() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
    }

    /// Fallback when Input Monitoring isn't granted (needs Accessibility).
    private func installFallbackMonitors() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { e in
            if let cg = e.cgEvent, cg.getIntegerValueField(.eventSourceUserData) == KeySender.marker { return }
            let type: CGEventType = e.type == .keyDown ? .keyDown : .leftMouseDown
            let loc = e.cgEvent?.location ?? .zero
            let code = Int64(e.type == .keyDown ? e.keyCode : 0)
            let flags = e.cgEvent?.flags ?? []
            MainActor.assumeIsolated {
                InputMonitor.shared.handle(type: type, keyCode: code, flags: flags, location: loc)
            }
        }) {
            globalMonitors.append(m)
        }
    }

    private func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags, location: CGPoint) {
        if type == .keyDown {
            if keyCode == 53 { onEscape?(); return }
            if HotkeyManager.shared.isHotkey(keyCode: keyCode, flags: flags) { return }
            onUserInterrupt?("key")
        } else {
            // CG global coords (top-left origin) → Cocoa (bottom-left origin).
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let p = NSPoint(x: location.x, y: primaryHeight - location.y)
            if SettingsStore.shared.bool(K.ignoreClicksOnOwnWindows) && WindowManager.shared.containsScreenPoint(p) { return }
            onUserInterrupt?("click")
        }
    }
}
