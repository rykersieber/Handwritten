import SwiftUI
import AppKit

/// Click, then press a key combo to record it. Escape cancels; Delete clears.
struct HotkeyRecorderView: View {
    let settingKey: String
    @ObservedObject var store = SettingsStore.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                Text(label)
                    .frame(minWidth: 110)
                    .foregroundStyle(recording ? ThemeStore.shared.accent : .primary)
            }
            .buttonStyle(.bordered)
            if !store.str(settingKey).isEmpty {
                Button {
                    store.set(settingKey, "")
                } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .help("Clear this hotkey")
            }
        }
        .onDisappear(perform: stop)
    }

    private var label: String {
        if recording { return "Press keys…" }
        guard let c = HotkeyCombo(storage: store.str(settingKey)) else { return "None" }
        return c.display
    }

    private func toggle() { recording ? stop() : startRecording() }

    private func startRecording() {
        recording = true
        HotkeyManager.shared.suspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Escape cancels
            let combo = HotkeyCombo(event: event)
            if combo.modifiers == 0 && !(122...126).contains(Int(event.keyCode)) && event.keyCode < 96 {
                NSSound.beep() // require a modifier for normal keys
                return nil
            }
            store.set(settingKey, combo.storage)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        HotkeyManager.shared.suspended = false
    }
}
