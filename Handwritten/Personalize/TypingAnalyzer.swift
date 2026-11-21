import Foundation

/// One recorded key press from the user (or from a simulated plan in tests).
struct RecordedKey {
    enum Kind: Equatable {
        case char(Character)
        case backspace
        case optionBackspace
        case left
        case right
        case other
    }
    var time: Double        // seconds, key-down
    var kind: Kind
    var hold: Double?       // key-down → key-up, if known
    var isRepeat = false    // auto-repeat from holding a key
}

/// What the analyzer found: setting values plus human-readable rows for the results screen.
struct TypingAnalysis {
    struct Row: Identifiable {
        let id = UUID()
        let key: String
        let title: String
        let value: Double
        let unit: String
        let note: String
    }
    var values: [String: SettingValue] = [:]
    var rows: [Row] = []
    var wpm: Double = 0
    var accuracy: Double = 1
    var corrections = 0
    var charsTyped = 0
    var duration: Double = 0
    var warnings: [String] = []
}

/// Turns a recording of real typing into Handwritten settings.
enum TypingAnalyzer {
    // MARK: Stats helpers

    private static func median(_ a: [Double]) -> Double? {
        guard !a.isEmpty else { return nil }
        let s = a.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    private static func percentile(_ a: [Double], _ p: Double) -> Double? {
        guard !a.isEmpty else { return nil }
        let s = a.sorted()
        let idx = min(s.count - 1, max(0, Int((Double(s.count - 1) * p).rounded())))
        return s[idx]
    }

    private static func trimmedMean(_ a: [Double], _ trim: Double = 0.1) -> Double? {
        guard !a.isEmpty else { return nil }
        let s = a.sorted()
        let cut = Int(Double(s.count) * trim)
        let mid = s.count > 2 * cut + 1 ? Array(s[cut..<(s.count - cut)]) : s
        return mid.reduce(0, +) / Double(mid.count)
    }

    private static func std(_ a: [Double]) -> Double {
        guard a.count > 1 else { return 0 }
        let m = a.reduce(0, +) / Double(a.count)
        return sqrt(a.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(a.count - 1))
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    // MARK: Analysis

    static func analyze(keys rawKeys: [RecordedKey], sample: String, finalText: String,
                        base: SettingsSnapshot, words: WordData.Snapshot) -> TypingAnalysis {
        var out = TypingAnalysis()
        let keys = rawKeys.filter { $0.kind != .other }
        guard keys.count >= 40 else {
            out.warnings.append("Not enough typing to analyze. Type at least a few sentences.")
            return out
        }

        // --- Intervals between key presses, labeled by what came before/after.
        struct Gap { let dt: Double; let prev: RecordedKey.Kind; let cur: RecordedKey.Kind; let index: Int }
        var gaps: [Gap] = []
        for i in 1..<keys.count {
            gaps.append(Gap(dt: keys[i].time - keys[i - 1].time, prev: keys[i - 1].kind, cur: keys[i].kind, index: i))
        }
        func ch(_ k: RecordedKey.Kind) -> Character? { if case .char(let c) = k { return c }; return nil }

        // Reconstruct which word each typed letter belongs to (for common-word bursts).
        var wordAt = [String?](repeating: nil, count: keys.count)
        var i0 = 0
        while i0 < keys.count {
            if let c = ch(keys[i0].kind), c.isLetter {
                var j = i0
                var w = ""
                while j < keys.count, let c2 = ch(keys[j].kind), c2.isLetter || c2 == "'" { w.append(c2); j += 1 }
                for k in i0..<j { wordAt[k] = w.lowercased() }
                i0 = j
            } else { i0 += 1 }
        }

        // In-word letter→letter gaps are the "pure speed" baseline.
        let inWord = gaps.filter { g in
            guard let a = ch(g.prev), let b = ch(g.cur) else { return false }
            return a.isLetter && b.isLetter && g.dt > 0.005 && g.dt < 1.0
        }
        guard inWord.count >= 20, let baseInterval = trimmedMean(inWord.map(\.dt)) else {
            out.warnings.append("Not enough letters typed to measure speed.")
            return out
        }
        var wpm = clamp(60.0 / (baseInterval * 5.0), 5, 250)

        // Variation: spread of log intervals (log-normal model uses sigma = variation × 0.6).
        let sigma = std(inWord.map { log($0.dt) })
        let variation = clamp(sigma / 0.6 * 100, 0, 150)

        // Pause after specific characters = extra time beyond the baseline.
        let thinkThreshold = max(1.2, baseInterval * 8)
        // The key after punctuation is usually the space bar, which the app types with its thumb/space timing.
        let spaceKeyTime = baseInterval * base.pct(K.finger(8)) * base.pct(K.row(4))
        // Uses a low percentile so the occasional "re-read" or thinking pause doesn't inflate it.
        func extraAfter(_ match: (Character) -> Bool, nextMatch: ((Character) -> Bool)? = nil, cutoff: Double = 8.0) -> (Double, Int)? {
            let ds = gaps.compactMap { g -> Double? in
                guard let a = ch(g.prev), match(a), let b = ch(g.cur) else { return nil }
                if let nm = nextMatch, !nm(b) { return nil }
                return g.dt < cutoff ? g.dt : nil
            }
            guard ds.count >= 2, let m = ds.count >= 5 ? median(ds) : percentile(ds, 0.25) else { return nil }
            return (max(0, (m - spaceKeyTime) * 1000), ds.count)
        }
        var v: [String: Double] = [:]
        var notes: [String: String] = [:]

        // Pause after a space: only before short, common, lowercase words, so word-start effects (rare/long
        // words, capitals) aren't counted twice. The app adds its own word-start slowdown on top.
        do {
            let longLen = base.int(K.longWordLength)
            let wordStartSlow = 1 + base.pct(K.wordStartMult)
            let ds = gaps.compactMap { g -> Double? in
                guard ch(g.prev) == " ", let b = ch(g.cur), b.isLowercase, g.dt < thinkThreshold,
                      let w = wordAt[g.index], words.common.contains(w), w.count < longLen else { return nil }
                return g.dt
            }
            if ds.count >= 4, let m = median(ds) {
                v[K.pauseSpace] = max(0, (m - baseInterval * wordStartSlow) * 1000)
                notes[K.pauseSpace] = "\(ds.count) spaces"
            }
        }
        if let (p, n) = extraAfter({ $0 == "," }) { v[K.pauseComma] = p; notes[K.pauseComma] = "\(n) commas" }
        // Sentence ends: pool . ! ? (followed by a space/new line). Much longer ones are "re-reading" pauses.
        let ends = gaps.compactMap { g -> Double? in
            guard let a = ch(g.prev), ".!?".contains(a), let b = ch(g.cur), b.isWhitespace, g.dt < 30 else { return nil }
            return g.dt
        }
        if ends.count >= 2, let low = percentile(ends, 0.0) {
            let rereadCut = max(1.5, low * 2.5)
            let normal = ends.filter { $0 < rereadCut }, rereads = ends.filter { $0 >= rereadCut }
            if let m = median(normal) {
                v[K.pausePeriod] = max(0, (m - spaceKeyTime) * 1000)
                v[K.pauseQuestion] = (v[K.pausePeriod] ?? 0) * 1.1
                notes[K.pausePeriod] = "\(normal.count) sentence ends"
            }
            v[K.rereadChance] = clamp(Double(rereads.count) / Double(ends.count) * 100, 0, 60)
            notes[K.rereadChance] = "\(rereads.count) of \(ends.count) sentence ends"
            if !rereads.isEmpty, let m = median(normal) {
                let extra = rereads.map { $0 - m }
                v[K.rereadMin] = clamp((extra.min() ?? 1.5) * 0.8, 0.1, 60)
                v[K.rereadMax] = clamp((extra.max() ?? 5) * 1.2, 0.2, 120)
            }
        }
        if let (p, n) = extraAfter({ $0 == ";" || $0 == ":" }) { v[K.pauseColon] = p; notes[K.pauseColon] = "\(n) : or ;" }
        if let (p, n) = extraAfter({ $0 == "\n" }) { v[K.pauseNewline] = p; notes[K.pauseNewline] = "\(n) new lines" }

        // Thinking pauses: long gaps right before a word starts.
        let wordStarts = gaps.filter { g in
            guard let b = ch(g.cur), b.isLetter else { return false }
            if let a = ch(g.prev) { return a == " " || a == "\n" }
            return false
        }
        let thinks = wordStarts.filter { $0.dt >= thinkThreshold }.map(\.dt)
        if wordStarts.count >= 10 {
            v[K.thinkChanceWord] = clamp(Double(thinks.count) / Double(wordStarts.count) * 100, 0, 50)
            if thinks.count >= 2, let lo = percentile(thinks, 0.15), let hi = percentile(thinks, 0.9) {
                v[K.thinkMin] = clamp(lo, 0.5, 60)
                v[K.thinkMax] = clamp(max(hi, lo + 0.2), 0.6, 120)
            }
            notes[K.thinkChanceWord] = "\(thinks.count) of \(wordStarts.count) words"
        }

        // Harder keys: compare against the baseline.
        func ratio(_ filter: (Gap) -> Bool, against ref: Double) -> (Double, Int)? {
            let ds = gaps.filter { $0.dt > 0.005 && $0.dt < 1.0 && filter($0) }.map(\.dt)
            guard ds.count >= 4, let m = median(ds) else { return nil }
            return (m / ref, ds.count)
        }
        let afterSpaceLower = gaps.filter { g in
            guard let a = ch(g.prev), let b = ch(g.cur) else { return false }
            return a == " " && b.isLowercase && g.dt < thinkThreshold
        }.map(\.dt)
        if let ref = median(afterSpaceLower), afterSpaceLower.count >= 4,
           let (r, n) = ratio({ g in ch(g.prev) == " " && (ch(g.cur)?.isUppercase ?? false) }, against: ref) {
            v[K.shiftPenalty] = clamp((r - 1) * 100, 0, 300); notes[K.shiftPenalty] = "\(n) capitals"
        }
        if let (r, n) = ratio({ g in ch(g.cur)?.isNumber ?? false }, against: baseInterval) {
            v[K.numberRowPenalty] = clamp((r - 1) * 100, 0, 300); notes[K.numberRowPenalty] = "\(n) digits"
        }
        if let (r, n) = ratio({ g in
            guard let c = ch(g.cur) else { return false }
            return !c.isLetter && !c.isNumber && !c.isWhitespace && (ch(g.prev)?.isLetter ?? false)
        }, against: baseInterval) {
            v[K.symbolPenalty] = clamp((r - 1) * 100, 0, 300); notes[K.symbolPenalty] = "\(n) symbols"
        }

        // Bursts: common letter pairs and common words vs everything else in a word.
        let pairs = inWord.map { g -> (Bool, Double) in
            let bg = (String(ch(g.prev)!) + String(ch(g.cur)!)).lowercased()
            return (words.bigrams.contains(bg), g.dt)
        }
        let commonPairs = pairs.filter(\.0).map(\.1), otherPairs = pairs.filter { !$0.0 }.map(\.1)
        if commonPairs.count >= 8, otherPairs.count >= 8, let a = median(commonPairs), let b = median(otherPairs) {
            v[K.bigramBurst] = clamp(a / b * 100, 20, 120); notes[K.bigramBurst] = "\(commonPairs.count) common pairs"
        }
        let wordGaps = inWord.map { g -> (Bool, Double) in (wordAt[g.index].map { words.common.contains($0) } ?? false, g.dt) }
        let inCommon = wordGaps.filter(\.0).map(\.1), inOther = wordGaps.filter { !$0.0 }.map(\.1)
        if inCommon.count >= 8, inOther.count >= 8, let a = median(inCommon), let b = median(inOther) {
            v[K.wordBurst] = clamp(a / b * 100, 20, 120); notes[K.wordBurst] = "\(inCommon.count) letters in common words"
        }

        // Key hold times.
        let holds = keys.compactMap(\.hold).filter { $0 > 0.003 && $0 < 0.5 }
        if holds.count >= 20, let lo = percentile(holds, 0.1), let hi = percentile(holds, 0.9) {
            v[K.holdMin] = clamp(lo * 1000, 1, 300); v[K.holdMax] = clamp(max(hi, lo + 0.005) * 1000, 2, 400)
            notes[K.holdMin] = "\(holds.count) key presses"
        }

        // Corrections: runs of backspaces.
        let episodes = correctionEpisodes(keys)
        let typedChars = keys.filter { if case .char = $0.kind { return true }; return false }.count
        out.corrections = episodes.count

        // Compare the finished text with the sample for typos left in.
        let fin = Array(finalText), samp = Array(sample)
        let compareTo = Array(samp.prefix(min(samp.count, fin.count + 3)))
        let leftIn = fin.isEmpty ? 0 : levenshtein(fin, compareTo)
        out.accuracy = fin.isEmpty ? 1 : max(0, 1 - Double(leftIn) / Double(max(1, compareTo.count)))

        // Typo amount: starting guess from the app's default rate; calibrated by simulation below.
        let defaultRate = defaultTyposPerChar(sample: sample, base: base, words: words)
        let errorsPerChar = Double(episodes.count + leftIn) / Double(max(1, fin.count))
        v[K.typoMaster] = defaultRate > 0 ? clamp(errorsPerChar / defaultRate * 100, 0, 400) : 100
        notes[K.typoMaster] = "\(episodes.count) fixes + \(leftIn) left in"
        if episodes.count + leftIn >= 2 {
            v[K.leaveUnfixed] = clamp(Double(leftIn) / Double(episodes.count + leftIn) * 100, 0, 100)
        }
        if episodes.count >= 3 {
            let imm = episodes.filter { $0.count == 1 && !$0.arrows }.count
            let del = episodes.filter { (2...4).contains($0.count) && !$0.arrows }.count
            let eow = episodes.filter { $0.count >= 5 && !$0.arrows }.count
            let late = episodes.filter(\.arrows).count
            let total = Double(imm + del + eow + late)
            v[K.fixImmediateWeight] = (Double(imm) / total * 100).rounded()
            v[K.fixDelayedWeight] = (Double(del) / total * 100).rounded()
            v[K.fixEndOfWordWeight] = (Double(eow) / total * 100).rounded()
            v[K.fixLateWeight] = (Double(late) / total * 100).rounded()
            notes[K.fixImmediateWeight] = "\(imm) right away, \(del) a few letters later, \(eow) at word end, \(late) with arrows"
            let notices = episodes.map(\.notice).filter { $0 > 0.02 && $0 < 5 }
            if notices.count >= 3, let lo = percentile(notices, 0.2), let hi = percentile(notices, 0.8) {
                v[K.noticeMin] = clamp(lo * 1000, 0, 5000); v[K.noticeMax] = clamp(max(hi, lo) * 1000, 0, 10000)
            }
            let inner = episodes.flatMap(\.inner).filter { $0 > 0.005 && $0 < 1 }
            if inner.count >= 3, let m = median(inner) {
                v[K.backspaceSpeed] = clamp(m / baseInterval * 100, 10, 300)
            }
            v[K.wordDeleteChance] = clamp(Double(episodes.filter(\.word).count) / Double(episodes.count) * 100, 0, 100)
        }

        // Warm-up and fatigue from how in-word speed changes across the run.
        let start = keys.first!.time, end = keys.last!.time
        out.duration = end - start
        let n = inWord.count
        if n >= 40 {
            let firstPart = Array(inWord.prefix(n / 6)).map(\.dt)
            let middle = Array(inWord[(n / 4)..<(3 * n / 4)]).map(\.dt)
            let lastPart = Array(inWord.suffix(n / 5)).map(\.dt)
            if let f = trimmedMean(firstPart), let m = trimmedMean(middle), let l = trimmedMean(lastPart), m > 0 {
                let warm = f / m
                v[K.warmupMult] = clamp(warm * 100, 100, 300)
                v[K.warmupSeconds] = warm > 1.08 ? clamp(out.duration * 0.2, 5, 60) : 0
                let minutes = max(0.5, out.duration / 60)
                v[K.fatiguePerMinute] = clamp((l / m - 1) * 100 / minutes, 0, 5)
            }
        }

        // Calibrate: simulate the app typing the same text with these settings, measure it exactly the way
        // we measured you, and nudge typo amount and speed until the simulation matches you.
        v[K.variation] = variation
        v[K.wpm] = wpm
        let simText = String(samp.prefix(max(fin.count, 20)))
        let userFixes = Double(episodes.count)
        for _ in 0..<5 {
            let (simDur, simFixes) = simulate(sample: simText, values: v, base: base, words: words)
            if let m = v[K.typoMaster], userFixes + Double(leftIn) > 0 {
                v[K.typoMaster] = clamp(m * (userFixes + 0.5) / (simFixes + 0.5), 0, 400)
            } else if userFixes == 0 && leftIn == 0 {
                v[K.typoMaster] = 0
            }
            guard simDur > 0, out.duration > 0 else { break }
            wpm = clamp(wpm * simDur / out.duration, 5, 250)
            v[K.wpm] = wpm
        }
        out.wpm = v[K.wpm] ?? wpm
        out.charsTyped = typedChars

        // Build results.
        let order: [(String, String, String)] = [
            (K.wpm, "Typing speed", "WPM"), (K.variation, "Speed variation", "%"),
            (K.pauseSpace, "Pause after a space", "ms"), (K.pauseComma, "Pause after a comma", "ms"),
            (K.pausePeriod, "Pause after a period", "ms"), (K.pauseQuestion, "Pause after ? or !", "ms"),
            (K.pauseColon, "Pause after : or ;", "ms"),
            (K.rereadChance, "Re-read pause chance", "%"), (K.rereadMin, "Re-read pause shortest", "s"),
            (K.rereadMax, "Re-read pause longest", "s"), (K.pauseNewline, "Pause after a new line", "ms"),
            (K.thinkChanceWord, "Thinking pause chance per word", "%"), (K.thinkMin, "Thinking pause shortest", "s"),
            (K.thinkMax, "Thinking pause longest", "s"),
            (K.shiftPenalty, "Capitals slower by", "%"), (K.numberRowPenalty, "Numbers slower by", "%"),
            (K.symbolPenalty, "Symbols slower by", "%"), (K.bigramBurst, "Common letter pair speed", "%"),
            (K.wordBurst, "Common word speed", "%"), (K.holdMin, "Key hold (min)", "ms"), (K.holdMax, "Key hold (max)", "ms"),
            (K.typoMaster, "Typo amount", "%"), (K.leaveUnfixed, "Typos left unfixed", "%"),
            (K.fixImmediateWeight, "Fix right away (weight)", ""), (K.fixDelayedWeight, "Fix a few letters later (weight)", ""),
            (K.fixEndOfWordWeight, "Fix at word end (weight)", ""), (K.fixLateWeight, "Fix much later (weight)", ""),
            (K.noticeMin, "Noticing delay (min)", "ms"), (K.noticeMax, "Noticing delay (max)", "ms"),
            (K.backspaceSpeed, "Backspace speed", "%"), (K.wordDeleteChance, "Delete whole word with ⌥⌫", "%"),
            (K.warmupSeconds, "Warm-up time", "s"), (K.warmupMult, "Warm-up start speed", "%"),
            (K.fatiguePerMinute, "Fatigue per minute", "%"),
        ]
        for (key, title, unit) in order {
            guard var val = v[key] else { continue }
            if let d = SettingsRegistry.def(key), case .number(let mn, let mx, let step, _) = d.kind {
                val = clamp(val, mn, mx)
                val = step >= 1 ? val.rounded() : (val / step).rounded() * step
            }
            out.values[key] = .number(val)
            out.rows.append(.init(key: key, title: title, value: val, unit: unit, note: notes[key] ?? ""))
        }
        if typedChars < Int(Double(samp.count) * 0.6) {
            out.warnings.append("You typed less than 60% of the sample, so some results are rough.")
        }
        if episodes.isEmpty && leftIn == 0 {
            out.warnings.append("No typos at all. Typo amount is set to 0; turn it up if you want some mistakes.")
        }
        return out
    }

    // MARK: Simulation helpers

    private static func snapshot(_ values: [String: Double], base: SettingsSnapshot, seed: Int) -> SettingsSnapshot {
        var vals = base.values
        for (k, x) in values { vals[k] = .number(x) }
        vals[K.speedMode] = .text("wpm")
        vals[K.useSeed] = .bool(true)
        vals[K.seed] = .number(Double(seed))
        vals[K.autocorrectProtection] = .text("off")
        return SettingsSnapshot(values: vals)
    }

    private static func defaultTyposPerChar(sample: String, base: SettingsSnapshot, words: WordData.Snapshot) -> Double {
        var total = 0, chars = 0
        for seed in 0..<12 {
            var vals = base.values
            for d in SettingsRegistry.all where Preset.typingTabs.contains(d.tab) { vals[d.key] = d.defaultValue }
            vals[K.typoMaster] = .number(100)
            vals[K.typosEnabled] = .bool(true)
            vals[K.useSeed] = .bool(true)
            vals[K.seed] = .number(Double(1000 + seed))
            vals[K.autocorrectProtection] = .text("off")
            let plan = Planner.makePlan(text: sample, settings: SettingsSnapshot(values: vals), words: words)
            total += plan.typoCount
            chars += sample.count
        }
        return chars > 0 ? Double(total) / Double(chars) : 0
    }

    /// Average duration and number of correction episodes when the app types `sample` with `values`.
    private static func simulate(sample: String, values: [String: Double], base: SettingsSnapshot, words: WordData.Snapshot) -> (Double, Double) {
        var dur = 0.0, fixes = 0.0
        let runs = 6
        for seed in 0..<runs {
            var snap = snapshot(values, base: base, seed: 50 + seed).values
            snap[K.proofreadAtEnd] = .bool(false) // people don't do a separate proofread pass in the sample
            let plan = Planner.makePlan(text: sample, settings: SettingsSnapshot(values: snap), words: words)
            dur += plan.totalDuration
            fixes += Double(correctionEpisodes(keys(from: plan)).count)
        }
        return (dur / Double(runs), fixes / Double(runs))
    }

    struct Episode { var count: Int; var word: Bool; var notice: Double; var inner: [Double]; var arrows: Bool }

    /// Groups runs of backspaces into correction episodes.
    static func correctionEpisodes(_ keys: [RecordedKey]) -> [Episode] {
        var episodes: [Episode] = []
        var idx = 0
        while idx < keys.count {
            let k = keys[idx]
            if k.kind == .backspace || k.kind == .optionBackspace {
                let notice = idx > 0 ? keys[idx].time - keys[idx - 1].time : 0
                let arrowsBefore = idx > 0 && (keys[idx - 1].kind == .left || keys[idx - 1].kind == .right)
                var e = Episode(count: 0, word: false, notice: notice, inner: [], arrows: arrowsBefore)
                while idx < keys.count, keys[idx].kind == .backspace || keys[idx].kind == .optionBackspace {
                    if keys[idx].kind == .optionBackspace { e.word = true; e.count += 4 } else { e.count += 1 }
                    if e.count > 1, !keys[idx].isRepeat { e.inner.append(keys[idx].time - keys[idx - 1].time) }
                    idx += 1
                }
                episodes.append(e)
            } else { idx += 1 }
        }
        return episodes
    }

    /// Converts a plan into the keystrokes a person would have made (for round-trip tests).
    static func keys(from plan: TypingPlan) -> [RecordedKey] {
        var t = 0.0
        var out: [RecordedKey] = []
        for st in plan.steps {
            t += st.delay
            let kind: RecordedKey.Kind
            switch st.action {
            case .char(let c): kind = .char(c)
            case .newline: kind = .char("\n")
            case .tab: kind = .char("\t")
            case .backspace: kind = .backspace
            case .optionBackspace: kind = .optionBackspace
            case .left: kind = .left
            case .right: kind = .right
            default: kind = .other
            }
            out.append(RecordedKey(time: t, kind: kind, hold: st.hold))
        }
        return out
    }
}
