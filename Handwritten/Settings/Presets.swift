import Foundation

struct Preset: Codable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    var detail: String = ""
    var builtIn: Bool = false
    var values: [String: SettingValue]

    /// Name shown when you're not on any preset (your own settings).
    static let customName = "Custom"

    /// Tabs whose settings belong to a typing preset.
    static let typingTabs: Set<SettingTab> = [.speed, .rhythm, .typos, .corrections]
}

@MainActor
final class PresetStore: ObservableObject {
    static let shared = PresetStore()

    @Published private(set) var userPresets: [Preset] = []

    var all: [Preset] { BuiltInPresets.all + userPresets }

    private var dir: URL {
        let d = SettingsStore.supportDir.appendingPathComponent("presets", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    init() { load() }

    func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        userPresets = files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Preset.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func preset(named name: String) -> Preset? { all.first { $0.name == name } }

    func save(_ p: Preset) {
        var p = p
        p.builtIn = false
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(p) {
            try? data.write(to: fileURL(p.name), options: .atomic)
        }
        load()
    }

    /// Names you can't use for your own presets.
    func isReserved(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        return n == Preset.customName.lowercased() || BuiltInPresets.all.contains { $0.name.lowercased() == n }
    }

    func saveCurrent(as name: String, detail: String = "") {
        let p = Preset(name: name, detail: detail, values: SettingsStore.shared.typingValuesForPreset())
        save(p)
        SettingsStore.shared.activePresetName = name
    }

    func delete(_ name: String) {
        try? FileManager.default.removeItem(at: fileURL(name))
        load()
    }

    func rename(_ old: String, to new: String) {
        guard var p = userPresets.first(where: { $0.name == old }) else { return }
        delete(old)
        p.name = new
        save(p)
        if SettingsStore.shared.activePresetName == old { SettingsStore.shared.activePresetName = new }
    }

    private func fileURL(_ name: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return dir.appendingPathComponent("\(safe).json")
    }
}

enum BuiltInPresets {
    private static func p(_ name: String, _ detail: String, _ v: [String: Double], bools: [String: Bool] = [:]) -> Preset {
        var values: [String: SettingValue] = v.mapValues { .number($0) }
        for (k, b) in bools { values[k] = .bool(b) }
        return Preset(name: name, detail: detail, builtIn: true, values: values)
    }

    static let all: [Preset] = [
        p("Hunt & Peck", "Slow, looks at the keyboard, lots of pauses.", [
            K.wpm: 22, K.variation: 70, K.typoMaster: 140, K.thinkChanceWord: 4, K.pausePeriod: 900,
            K.pauseNewline: 1500, K.shiftPenalty: 90, K.symbolPenalty: 90, K.numberRowPenalty: 80,
            K.bigramBurst: 95, K.wordBurst: 90, K.fixImmediateWeight: 70, K.fixLateWeight: 2, K.leaveUnfixed: 2,
            K.noticeMin: 400, K.noticeMax: 1300, K.backspaceSpeed: 90,
        ]),
        p("Casual", "Relaxed everyday typing.", [
            K.wpm: 42, K.variation: 45, K.typoMaster: 110, K.thinkChanceWord: 2.5, K.pausePeriod: 600,
        ]),
        p("Average Student", "Typical school essay pace with normal mistakes.", [:]),
        p("Office Worker", "Steady and accurate.", [
            K.wpm: 62, K.variation: 30, K.typoMaster: 80, K.thinkChanceWord: 1.5, K.leaveUnfixed: 2,
        ]),
        p("Fast Typist", "Quick with bursts and quick fixes.", [
            K.wpm: 90, K.variation: 28, K.typoMaster: 90, K.bigramBurst: 65, K.wordBurst: 58,
            K.fixImmediateWeight: 60, K.noticeMin: 100, K.noticeMax: 350, K.backspaceSpeed: 40,
            K.pausePeriod: 300, K.pauseNewline: 450, K.thinkChanceWord: 1,
        ]),
        p("Pro Typist", "Very fast, very accurate.", [
            K.wpm: 125, K.variation: 20, K.typoMaster: 45, K.bigramBurst: 60, K.wordBurst: 55,
            K.fixImmediateWeight: 80, K.fixLateWeight: 2, K.leaveUnfixed: 0, K.noticeMin: 60, K.noticeMax: 220,
            K.backspaceSpeed: 35, K.pausePeriod: 220, K.pauseNewline: 350, K.thinkChanceWord: 0.5,
            K.shiftPenalty: 15, K.symbolPenalty: 15,
        ]),
        p("Programmer", "Fast on words, slower on symbols, thinks between lines.", [
            K.wpm: 70, K.symbolPenalty: 60, K.shiftPenalty: 40, K.pauseNewline: 1100, K.pauseBracket: 250,
            K.thinkChanceParagraph: 60, K.typoMaster: 70, K.leaveUnfixed: 0,
        ]),
        p("Careful Writer", "Few typos, lots of pauses to think.", [
            K.wpm: 48, K.typoMaster: 40, K.thinkChanceWord: 4, K.thinkChanceSentence: 25, K.thinkMax: 8,
            K.rereadChance: 15, K.fixImmediateWeight: 75, K.leaveUnfixed: 0,
        ]),
        p("Essay Thinker", "Writes like composing an essay from scratch: long thinking pauses.", [
            K.wpm: 45, K.thinkChanceWord: 5, K.thinkChanceSentence: 35, K.thinkChanceParagraph: 80,
            K.thinkMin: 2, K.thinkMax: 15, K.rereadChance: 20, K.rereadMax: 10, K.pauseParagraph: 4000,
        ], bools: [K.breakEnabled: true]),
        p("Late-Night Tired", "Slow, sloppy, getting worse over time.", [
            K.wpm: 38, K.variation: 65, K.typoMaster: 190, K.fatiguePerMinute: 2.5, K.fatigueMax: 60,
            K.typoFatigueMult: 150, K.hesitationChance: 10, K.leaveUnfixed: 8, K.noticeMax: 1400,
        ]),
        p("Chat Messenger", "Quick bursts, casual mistakes.", [
            K.wpm: 70, K.variation: 40, K.randomBurstChance: 20, K.typoMaster: 120, K.pausePeriod: 250,
            K.thinkChanceWord: 1, K.fixImmediateWeight: 65,
        ]),
        p("Instant", "No human effects at all. Just types fast.", [
            K.wpm: 250, K.variation: 0, K.driftAmount: 0, K.typoMaster: 0, K.pausePeriod: 0, K.pauseComma: 0,
            K.pauseSpace: 0, K.pauseNewline: 0, K.pauseParagraph: 0, K.pauseQuestion: 0, K.pauseColon: 0,
            K.pauseDash: 0, K.pauseQuote: 0, K.pauseBracket: 0, K.longWordPause: 0, K.rareWordChance: 0,
            K.hesitationChance: 0, K.rereadChance: 0, K.warmupSeconds: 0, K.fatiguePerMinute: 0,
            K.shiftPenalty: 0, K.symbolPenalty: 0, K.numberRowPenalty: 0, K.unicodePenalty: 0,
            K.minKeyDelay: 8, K.holdMin: 8, K.holdMax: 12,
        ], bools: [K.typosEnabled: false, K.thinkEnabled: false]),
    ]
}
