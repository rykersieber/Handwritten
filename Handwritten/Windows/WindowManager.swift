import AppKit
import SwiftUI

/// Creates and tracks the app's floating panels.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    enum ID: String, CaseIterable {
        case onboarding, controlPanel, settings, hud, historyEditor, dataEditor, personalize
    }

    private var windows: [ID: NSWindow] = [:]
    /// Windows that were visible when mask mode turned on, so we can restore them.
    private var maskedVisible: Set<ID> = []

    func window(_ id: ID) -> NSWindow? { windows[id] }

    func isVisible(_ id: ID) -> Bool { windows[id]?.isVisible ?? false }

    /// Show (or bring to front) a standard floating panel.
    func show<V: View>(_ id: ID,
                       title: String,
                       size: NSSize,
                       resizable: Bool = false,
                       floating: Bool = true,
                       activate: Bool = true,
                       @ViewBuilder content: () -> V) {
        if AppState.shared.isMasked { return }
        if let w = windows[id] {
            if activate { NSApp.activate(ignoringOtherApps: true) }
            w.makeKeyAndOrderFront(nil)
            return
        }
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if resizable { style.insert(.resizable) }
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: style,
                            backing: .buffered,
                            defer: false)
        panel.title = title
        panel.isFloatingPanel = floating
        panel.level = floating ? .floating : .normal
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.titlebarAppearsTransparent = false
        panel.delegate = self
        let host = NSHostingView(rootView: content().environmentObject(ThemeStore.shared))
        panel.contentView = host
        if resizable {
            panel.setContentSize(size)
            panel.minSize = NSSize(width: min(size.width, 520), height: min(size.height, 360))
        } else {
            panel.setContentSize(host.fittingSize.width > 10 ? host.fittingSize : size)
        }
        panel.setFrameAutosaveName("Handwritten.\(id.rawValue)")
        if !panel.setFrameUsingName("Handwritten.\(id.rawValue)") { panel.center() }
        windows[id] = panel
        if activate { NSApp.activate(ignoringOtherApps: true) }
        panel.makeKeyAndOrderFront(nil)
    }

    /// Show a non-activating HUD that never steals keyboard focus from the target app.
    func showHUD<V: View>(_ id: ID, size: NSSize, @ViewBuilder content: () -> V) {
        if AppState.shared.isMasked { return }
        if let w = windows[id] { w.orderFrontRegardless(); return }
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: content().environmentObject(ThemeStore.shared))
        panel.setFrameAutosaveName("Handwritten.\(id.rawValue)")
        if !panel.setFrameUsingName("Handwritten.\(id.rawValue)"), let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.maxX - size.width - 24, y: f.maxY - size.height - 24))
        }
        windows[id] = panel
        panel.orderFrontRegardless()
    }

    func close(_ id: ID) {
        windows[id]?.close()
    }

    func destroy(_ id: ID) {
        windows[id]?.close()
        windows[id] = nil
    }

    /// True if a screen point (Cocoa coordinates) is inside one of our visible windows.
    func containsScreenPoint(_ p: NSPoint) -> Bool {
        windows.values.contains { $0.isVisible && $0.frame.contains(p) }
    }

    // MARK: Mask support

    func hideAllForMask() {
        maskedVisible = Set(windows.filter { $0.value.isVisible }.map { $0.key })
        for w in windows.values { w.orderOut(nil) }
    }

    func restoreAfterMask() {
        for id in maskedVisible {
            if id == .hud { windows[id]?.orderFrontRegardless() } else { windows[id]?.orderFront(nil) }
        }
        maskedVisible = []
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Panels are reused; nothing to do. Return to accessory activation if no windows remain.
        DispatchQueue.main.async {
            AppDelegate.shared?.updateActivationPolicy()
        }
    }
}
