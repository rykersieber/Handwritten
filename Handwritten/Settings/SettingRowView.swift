import SwiftUI
import AppKit

/// One row in the settings window, rendered from its SettingDef.
struct SettingRowView: View {
    let def: SettingDef
    var showTab = false
    @ObservedObject private var store = SettingsStore.shared

    private var enabled: Bool {
        guard let dep = def.dependsOn else { return true }
        return store.bool(dep)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(def.title).font(.body)
                    if store.isChanged(def.key) {
                        Circle().fill(ThemeStore.shared.accent).frame(width: 6, height: 6).help("Changed from default")
                    }
                    if store.manualOverrides.contains(def.key) && def.human != nil {
                        Image(systemName: "hand.raised.fill").font(.caption2).foregroundStyle(.secondary)
                            .help("Set by hand: the Humanness slider won't change this.")
                    }
                    if showTab {
                        Text(def.tab.title).font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
                if !def.help.isEmpty {
                    Text(def.help).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control.frame(width: controlWidth, alignment: .trailing)
            Button { store.reset(def.key) } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(.borderless)
                .opacity(store.isChanged(def.key) ? 1 : 0.25)
                .disabled(!store.isChanged(def.key))
                .help("Reset to default")
        }
        .padding(.vertical, 4)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

    private var controlWidth: CGFloat {
        switch def.kind {
        case .number: return 260
        case .toggle: return 60
        case .choice: return 220
        case .text, .hotkey, .color: return 220
        }
    }

    @ViewBuilder private var control: some View {
        switch def.kind {
        case .number(let mn, let mx, let step, let unit):
            NumberControl(key: def.key, min: mn, max: mx, step: step, unit: unit)
        case .toggle:
            Toggle("", isOn: Binding(get: { store.bool(def.key) }, set: { store.set(def.key, $0) }))
                .toggleStyle(.switch).labelsHidden()
        case .choice(let options):
            Picker("", selection: Binding(get: { store.str(def.key) }, set: { v in
                if def.key == K.typingInto { TypingProfiles.apply(v) } else { store.set(def.key, v) }
            })) {
                ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
            }
            .labelsHidden()
        case .text(let placeholder):
            TextField(placeholder, text: Binding(get: { store.str(def.key) }, set: { store.set(def.key, $0) }))
                .textFieldStyle(.roundedBorder)
        case .hotkey:
            HotkeyRecorderView(settingKey: def.key)
        case .color:
            ColorPicker("", selection: Binding(
                get: { Color(nsColor: NSColor(hex: store.str(def.key)) ?? .systemBlue) },
                set: { c in
                    store.set(def.key, NSColor(c).hexString)
                    store.set(K.accent, "custom")
                }), supportsOpacity: false)
                .labelsHidden()
        }
    }
}

private struct NumberControl: View {
    let key: String
    let min: Double
    let max: Double
    let step: Double
    let unit: String
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        HStack(spacing: 6) {
            Slider(value: Binding(get: { Swift.min(max, Swift.max(min, store.num(key))) },
                                  set: { store.set(key, snap($0)) }),
                   in: min...max)
            TextField("", value: Binding(get: { store.num(key) },
                                         set: { store.set(key, Swift.min(max, Swift.max(min, $0))) }),
                      format: .number.precision(.fractionLength(0...(step < 1 ? 2 : 0))))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
        }
    }

    private func snap(_ v: Double) -> Double {
        guard step > 0 else { return v }
        let r = (v / step).rounded() * step
        return step < 1 ? (r * 100).rounded() / 100 : r
    }
}
