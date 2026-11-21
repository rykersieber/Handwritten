import Foundation

/// Word lists that drive speed bursts and dictionary typos.
/// Bundled copies live in the app; editable copies live in Application Support/Handwritten/data.
final class WordData: @unchecked Sendable {
    static let shared = WordData()

    enum File: String, CaseIterable, Identifiable {
        case commonWords = "common_words"
        case bigrams = "common_bigrams"
        case misspellings = "misspellings"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .commonWords: return "Common words (speed bursts)"
            case .bigrams: return "Common letter pairs (speed bursts)"
            case .misspellings: return "Misspellings (built-in typos)"
            }
        }
        var help: String {
            switch self {
            case .commonWords: return "One word per line. These are typed faster, like a real typist who knows them by heart. Lines starting with # are ignored."
            case .bigrams: return "One letter pair (or triple) per line, like th, er, ing. These get a small speed-up."
            case .misspellings: return "Format: correct: wrong1, wrong2. When the correct word appears, it may be misspelled as one of the wrong versions, then fixed."
            }
        }
    }

    private let lock = NSLock()
    private(set) var commonWords: Set<String> = []
    private(set) var commonWordList: [String] = []
    private(set) var bigrams: Set<String> = []
    private(set) var misspellings: [String: [String]] = [:]
    private var wordsByFirstLetter: [Character: [String]] = [:]

    static var dataDir: URL {
        let d = SettingsStore.supportDirNonisolated.appendingPathComponent("data", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func userURL(_ f: File) -> URL { dataDir.appendingPathComponent("\(f.rawValue).txt") }
    static func bundledURL(_ f: File) -> URL? { Bundle.main.url(forResource: f.rawValue, withExtension: "txt") }

    /// Copy bundled files to the user's folder on first run, then load.
    func installAndLoad() {
        for f in File.allCases {
            let u = Self.userURL(f)
            if !FileManager.default.fileExists(atPath: u.path), let b = Self.bundledURL(f) {
                try? FileManager.default.copyItem(at: b, to: u)
            }
        }
        reload()
    }

    func restoreDefault(_ f: File) {
        let u = Self.userURL(f)
        try? FileManager.default.removeItem(at: u)
        if let b = Self.bundledURL(f) { try? FileManager.default.copyItem(at: b, to: u) }
        reload()
    }

    static func read(_ f: File) -> String {
        if let s = try? String(contentsOf: userURL(f), encoding: .utf8) { return s }
        if let b = bundledURL(f), let s = try? String(contentsOf: b, encoding: .utf8) { return s }
        return ""
    }

    static func write(_ f: File, _ text: String) {
        try? text.write(to: userURL(f), atomically: true, encoding: .utf8)
        WordData.shared.reload()
    }

    private static func lines(_ s: String) -> [String] {
        s.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    func reload() {
        let words = Self.lines(Self.read(.commonWords)).map { $0.lowercased() }
        let pairs = Set(Self.lines(Self.read(.bigrams)).map { $0.lowercased() })
        var miss: [String: [String]] = [:]
        for line in Self.lines(Self.read(.misspellings)) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let correct = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let wrongs = parts[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty && $0 != correct }
            if !correct.isEmpty && !wrongs.isEmpty { miss[correct, default: []] += wrongs }
        }
        var byFirst: [Character: [String]] = [:]
        for w in words where w.count >= 2 { if let f = w.first { byFirst[f, default: []].append(w) } }

        lock.lock()
        commonWordList = words
        commonWords = Set(words)
        bigrams = pairs
        misspellings = miss
        wordsByFirstLetter = byFirst
        lock.unlock()
    }

    /// A different common word that starts with the same letter and has a similar length.
    func similarWord(to word: String, rng: inout RNG) -> String? {
        guard let f = word.lowercased().first else { return nil }
        lock.lock(); let pool = wordsByFirstLetter[f] ?? []; lock.unlock()
        let candidates = pool.filter { $0 != word.lowercased() && abs($0.count - word.count) <= 2 }
        return rng.pick(candidates)
    }

    struct Snapshot {
        let common: Set<String>
        let bigrams: Set<String>
        let misspellings: [String: [String]]
    }

    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(common: commonWords, bigrams: bigrams, misspellings: misspellings)
    }
}

extension SettingsStore {
    /// Same as `supportDir` but callable from any thread.
    nonisolated static var supportDirNonisolated: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Handwritten", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
