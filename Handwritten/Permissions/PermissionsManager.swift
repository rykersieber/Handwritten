import AppKit
import ApplicationServices

/// Tracks the two permissions the app needs:
/// - Accessibility: post keystrokes into other apps, read focused text for verification.
/// - Input Monitoring: listen for Escape / user clicks to stop or auto-pause.
@MainActor
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published private(set) var accessibility = false
    @Published private(set) var inputMonitoring = false

    private var timer: Timer?

    var allGranted: Bool { accessibility && inputMonitoring }

    func refresh() {
        let ax = AXIsProcessTrusted()
        let im = CGPreflightListenEventAccess()
        if ax != accessibility { accessibility = ax }
        if im != inputMonitoring { inputMonitoring = im }
    }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        openPane("Privacy_Accessibility")
    }

    func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        openPane("Privacy_ListenEvent")
    }

    func openPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    func startPolling() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
}
