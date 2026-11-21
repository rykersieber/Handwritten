import Foundation
import Combine

/// Immutable copy of all setting values; safe to hand to the typing thread.
struct SettingsSnapshot {
    let values: [String: SettingValue]

    func num(_ key: String) -> Double {
        if let v = values[key]?.number { return v }
        return SettingsRegistry.def(key)?.defaultValue.number ?? 0
    }
    func int(_ key: String) -> Int { Int(num(key).rounded()) }
    /// Percent settings are stored 0...100; this returns 0...1.
    func pct(_ key: String) -> Double { num(key) / 100.0 }
    /// Milliseconds → seconds.
    func ms(_ key: String) -> Double { num(key) / 1000.0 }
    func bool(_ key: String) -> Bool {
        if let v = values[key]?.bool { return v }
        return SettingsRegistry.def(key)?.defaultValue.bool ?? false
    }
    func str(_ key: String) -> String {
        if let v = values[key]?.text { return v }
        return SettingsRegistry.def(key)?.defaultValue.text ?? ""
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    /// Only values that differ from defaults are stored.
    @Published private(set) var values: [String: SettingValue] = [:]
    /// Keys the user set by hand; the humanness slider will not move them.
    @Published private(set) var manualOverrides: Set<String> = []
    @Published var uiLevel: SettingLevel = .simple { didSet { scheduleSave() } }
    @Published var activePresetName: String = "Average Student" { didSet { scheduleSave() } }

    private var saveWork: DispatchWorkItem?

    private struct Persisted: Codable {
        var values: [String: SettingValue]
        var manual: [String]
        var uiLevel: Int
        var preset: String
    }

    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Handwritten", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var fileURL: URL { Self.supportDir.appendingPathComponent("settings.json") }

    init() { load() }

    var snapshot: SettingsSnapshot {
        var merged: [String: SettingValue] = [:]
        for d in SettingsRegistry.all { merged[d.key] = d.defaultValue }
        for (k, v) in values { merged[k] = v }
        return SettingsSnapshot(values: merged)
    }

    // MARK: Read

    func value(_ key: String) -> SettingValue {
        values[key] ?? SettingsRegistry.def(key)?.defaultValue ?? .number(0)
    }
    func num(_ key: String) -> Double { value(key).number ?? 0 }
    func int(_ key: String) -> Int { Int(num(key).rounded()) }
    func pct(_ key: String) -> Double { num(key) / 100 }
    func bool(_ key: String) -> Bool { value(key).bool ?? false }
    func str(_ key: String) -> String { value(key).text ?? "" }

    func isChanged(_ key: String) -> Bool {
        guard let v = values[key], let d = SettingsRegistry.def(key) else { return false }
        return v != d.defaultValue
    }

    // MARK: Write

    /// Set a value as the user (marks it as a manual override for the humanness slider).
    func set(_ key: String, _ value: SettingValue, manual: Bool = true) {
        let changed = self.value(key) != value
        store(key, value)
        // Changing a typing setting by hand means you're no longer on a preset.
        if manual && changed && isTypingSetting(key) { activePresetName = Preset.customName }
        if manual && key != K.humanness {
            if SettingsRegistry.def(key)?.human != nil { manualOverrides.insert(key) }
        }
        if key == K.humanness, let h = value.number { applyHumanness(h) }
        scheduleSave()
        SettingsStore.didChange.send(key)
    }

    func set(_ key: String, _ v: Double) { set(key, .number(v)) }
    func set(_ key: String, _ v: Bool) { set(key, .bool(v)) }
    func set(_ key: String, _ v: String) { set(key, .text(v)) }

    private func store(_ key: String, _ value: SettingValue) {
        if let d = SettingsRegistry.def(key), d.defaultValue == value {
            values.removeValue(forKey: key)
        } else {
            values[key] = value
        }
    }

    func reset(_ key: String) {
        if isChanged(key) && isTypingSetting(key) { activePresetName = Preset.customName }
        values.removeValue(forKey: key)
        manualOverrides.remove(key)
        scheduleSave()
        SettingsStore.didChange.send(key)
    }

    func resetAll() {
        values = [:]
        manualOverrides = []
        activePresetName = Preset.customName
        scheduleSave()
        SettingsStore.didChange.send("*")
    }

    func clearManualOverrides() {
        manualOverrides = []
        applyHumanness(num(K.humanness))
        scheduleSave()
    }

    /// Replace everything with a preset's values (on top of defaults).
    func apply(preset: Preset) {
        // Keep non-typing settings (hotkeys, appearance, clipboard, mask, general UI) as they are.
        let keep = values.filter { key, _ in
            guard let tab = SettingsRegistry.def(key)?.tab else { return false }
            return !Preset.typingTabs.contains(tab)
        }
        values = keep
        for (k, v) in preset.values { store(k, v) }
        manualOverrides = Set(preset.values.keys.filter { SettingsRegistry.def($0)?.human != nil })
        activePresetName = preset.name
        scheduleSave()
        SettingsStore.didChange.send("*")
    }

    var isCustom: Bool { activePresetName == Preset.customName }

    /// Switch to "Custom" (no preset) without changing any values.
    func useCustom() { activePresetName = Preset.customName }

    func isTypingSetting(_ key: String) -> Bool {
        guard let tab = SettingsRegistry.def(key)?.tab else { return false }
        return Preset.typingTabs.contains(tab)
    }

    /// Typing-related values that differ from defaults (what a preset stores).
    func typingValuesForPreset() -> [String: SettingValue] {
        values.filter { key, _ in
            guard let tab = SettingsRegistry.def(key)?.tab else { return false }
            return Preset.typingTabs.contains(tab)
        }
    }

    // MARK: Test hooks
    func _testState() -> (values: [String: SettingValue], manual: Set<String>, preset: String, level: SettingLevel) {
        (values, manualOverrides, activePresetName, uiLevel)
    }
    func _testRestore(_ st: (values: [String: SettingValue], manual: Set<String>, preset: String, level: SettingLevel)) {
        values = st.values; manualOverrides = st.manual; activePresetName = st.preset; uiLevel = st.level
        saveNow()
        SettingsStore.didChange.send("*")
    }

    // MARK: Humanness

    /// Moves every human-scaled setting along its curve, skipping manual overrides.
    private func applyHumanness(_ h: Double) {
        let t = max(0, min(100, h)) / 100.0
        for d in SettingsRegistry.all {
            guard let (lo, hi) = d.human, !manualOverrides.contains(d.key),
                  let def = d.defaultValue.number else { continue }
            // Piecewise: 0 → lo, 0.5 → default, 1 → hi, with smoothstep inside each half.
            let v: Double
            if t <= 0.5 {
                let u = smooth(t / 0.5)
                v = lo + (def - lo) * u
            } else {
                let u = smooth((t - 0.5) / 0.5)
                v = def + (hi - def) * u
            }
            var clamped = v
            if case .number(let mn, let mx, let step, _) = d.kind {
                clamped = min(mx, max(mn, v))
                if step >= 1 { clamped = clamped.rounded() }
                else if step > 0 { clamped = (clamped / step).rounded() * step }
            }
            store(d.key, .number(clamped))
        }
    }

    private func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let p = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        values = p.values
        manualOverrides = Set(p.manual)
        uiLevel = SettingLevel(rawValue: p.uiLevel) ?? .simple
        activePresetName = p.preset
    }

    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        let p = Persisted(values: values, manual: Array(manualOverrides), uiLevel: uiLevel.rawValue, preset: activePresetName)
        if let data = try? JSONEncoder().encode(p) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Export / import

    struct ExportBundle: Codable {
        var version: Int = 1
        var settings: [String: SettingValue]
        var presets: [Preset]
    }

    func exportBundle(includePresets: Bool) -> Data? {
        let b = ExportBundle(settings: values, presets: includePresets ? PresetStore.shared.userPresets : [])
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(b)
    }

    func importBundle(_ data: Data) throws {
        let b = try JSONDecoder().decode(ExportBundle.self, from: data)
        values = b.settings.filter { SettingsRegistry.def($0.key) != nil }
        for p in b.presets { PresetStore.shared.save(p) }
        scheduleSave()
        SettingsStore.didChange.send("*")
    }

    /// Fires with the changed key ("*" for many).
    nonisolated(unsafe) static let didChange = PassthroughSubject<String, Never>()
}
