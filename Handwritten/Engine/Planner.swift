import Foundation

// MARK: - Text preparation

enum TextPreparer {
    private static let invisibleScalars: Set<UInt32> = [0x200B, 0x200C, 0x200D, 0xFEFF, 0x2060, 0x00AD]

    static func prepare(_ raw: String, _ s: SettingsSnapshot) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
        if s.bool(K.nbspToSpace) {
            text = text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
        }
        if s.bool(K.stripZeroWidth) {
            // Drop characters made only of invisible scalars (keeps emoji ZWJ sequences intact).
            text = String(text.filter { ch in !ch.unicodeScalars.allSatisfy { invisibleScalars.contains($0.value) } })
        }
        if s.bool(K.smartQuotesToStraight) {
            text = text.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
                .replacingOccurrences(of: "‘", with: "'").replacingOccurrences(of: "’", with: "'")
        }
        var lines = text.components(separatedBy: "\n")
        if s.bool(K.trimTrailingWhitespace) {
            lines = lines.map { l in
                var l = l
                while let last = l.last, last == " " || last == "\t" { l.removeLast() }
                return l
            }
        }
        if s.bool(K.codeMode) && s.str(K.codeIndentMode) == "strip" {
            lines = lines.map { String($0.drop(while: { $0 == " " || $0 == "\t" })) }
        }
        text = lines.joined(separator: "\n")
        if s.bool(K.collapseBlankLines) {
            while text.contains("\n\n\n") { text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        }
        if s.bool(K.trimEnds) { text = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if s.str(K.tabMode) == "spaces" {
            text = text.replacingOccurrences(of: "\t", with: String(repeating: " ", count: max(1, s.int(K.tabSpaces))))
        }
        let maxC = s.int(K.maxChars)
        if maxC > 0 && text.count > maxC { text = String(text.prefix(maxC)) }
        return text
    }
}

// MARK: - System text settings

/// Reads the Mac's own text-correction settings (System Settings → Keyboard → Text Input).
enum SystemText {
    private static func flag(_ key: String, default def: Bool = true) -> Bool {
        (UserDefaults.standard.object(forKey: key) as? Bool) ?? def
    }
    static var autocorrectOn: Bool { flag("NSAutomaticSpellingCorrectionEnabled") || flag("WebAutomaticSpellingCorrectionEnabled") }
    static var autoCapitalizeOn: Bool { flag("NSAutomaticCapitalizationEnabled") }
    static var doubleSpacePeriodOn: Bool { flag("NSAutomaticPeriodSubstitutionEnabled") }
    static var smartQuotesOn: Bool { flag("NSAutomaticQuoteSubstitutionEnabled") }

    static func doubleSpaceGuardActive(_ s: SettingsSnapshot) -> Bool {
        switch s.str(K.doubleSpaceGuard) {
        case "on": return true
        case "off": return false
        default: return doubleSpacePeriodOn
        }
    }

    static func protectionActive(_ s: SettingsSnapshot) -> Bool {
        switch s.str(K.autocorrectProtection) {
        case "on": return true
        case "off": return false
        default: return autocorrectOn
        }
    }
}

// MARK: - Planner

/// Builds the complete keystroke plan for a text. Pure simulation: no keys are sent here.
struct Planner {
    private enum FixMode { case immediate, delayed, endOfWord, late }
    private enum TypoKind: CaseIterable {
        case neighbor, transpose, double, skip, shift, shiftHold, fatFinger, mirror, space, punct
    }

    private struct Pending {
        var startBuf: Int
        var wrong: [Character]
        var correct: [Character]
        var targetStart: Int
        var mode: FixMode
        var remaining: Int
    }

    private struct Unfixed {
        var startBuf: Int
        var wrong: [Character]
        var correct: [Character]
    }

    private struct CharInfo {
        var wordId = -1
        var posInWord = 0
        var typoOK = true
    }

    // Inputs
    private let s: SettingsSnapshot
    private let words: WordData.Snapshot
    private let target: [Character]
    private let n: Int
    private var rng: RNG

    // Derived
    private let baseInterval: Double
    private let safe: Bool
    private let spaceGuard: Bool
    private let code: Bool
    private let typosOn: Bool
    private let dist: String
    private var info: [CharInfo]
    private var wordRanges: [Range<Int>] = []
    private var wordStrings: [String] = []
    private var capsWord: [Bool] = []

    // State
    private var steps: [Step] = []
    private var buffer: [Character] = []
    private var i = 0
    private var elapsed = 0.0
    private var carryPause = 0.0
    private var prevKey: KeyInfo?
    private var prevChar: Character?
    private var groupCounter = 0
    private var currentGroup = -1
    private var progressOverride: Int?
    private var pending: Pending?
    private var unfixed: [Unfixed] = []
    private var typoCount = 0
    private var charsSinceTypo = 1_000
    private var typosInWord = 0
    private var burstLeft = 0
    private var wordBurstActive = false
    private var lastWasBurst = false
    private var hesitationAt = -1
    private var lastBreakAt = -1e9
    private var lastMinuteChecked = 0
    private let driftPhase: Double

    static func makePlan(text: String, settings: SettingsSnapshot, words: WordData.Snapshot) -> TypingPlan {
        var p = Planner(text: text, settings: settings, words: words)
        return p.run()
    }

    private init(text: String, settings: SettingsSnapshot, words: WordData.Snapshot) {
        s = settings
        self.words = words
        target = Array(text)
        n = target.count
        rng = settings.bool(K.useSeed) ? RNG(seed: UInt64(max(0, settings.num(K.seed)))) : RNG()
        let wpm = max(1, settings.num(K.wpm))
        baseInterval = 60.0 / (wpm * 5.0)
        code = settings.bool(K.codeMode)
        safe = settings.bool(K.safeTypoMode) || SystemText.protectionActive(settings)
        spaceGuard = SystemText.doubleSpaceGuardActive(settings)
        typosOn = settings.bool(K.typosEnabled) && settings.num(K.typoMaster) > 0
        dist = settings.str(K.distribution)
        info = Array(repeating: CharInfo(), count: target.count)
        driftPhase = rng.range(0, 2 * .pi)
        analyze()
    }

    // MARK: Analysis

    private static func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber }

    private mutating func analyze() {
        // Words
        var k = 0
        while k < n {
            if Self.isWordChar(target[k]) {
                var e = k
                while e < n {
                    let c = target[e]
                    if Self.isWordChar(c) { e += 1; continue }
                    if (c == "'" || c == "’"), e + 1 < n, Self.isWordChar(target[e + 1]) { e += 1; continue }
                    break
                }
                let id = wordRanges.count
                wordRanges.append(k..<e)
                let w = String(target[k..<e])
                wordStrings.append(w.lowercased())
                let letters = w.filter(\.isLetter)
                capsWord.append(letters.count >= 2 && letters.allSatisfy(\.isUppercase))
                for j in k..<e { info[j].wordId = id; info[j].posInWord = j - k }
                k = e
            } else { k += 1 }
        }

        // Skip zones by whitespace-delimited token
        var t = 0
        while t < n {
            if target[t].isWhitespace { t += 1; continue }
            var e = t
            while e < n && !target[e].isWhitespace { e += 1 }
            let token = String(target[t..<e])
            if tokenSkipsTypos(token) { for j in t..<e { info[j].typoOK = false } }
            t = e
        }

        // Per word / per char rules
        let shortLimit = s.int(K.typoSkipShortWords)
        let firstWords = s.int(K.typoSkipFirstWords)
        for (id, r) in wordRanges.enumerated() {
            var skip = r.count < shortLimit || id < firstWords
            if s.bool(K.typoSkipAllCaps) && capsWord[id] { skip = true }
            if s.bool(K.typoSkipCapitalized), let f = target[r.lowerBound] as Character?, f.isUppercase,
               !isSentenceStart(r.lowerBound) { skip = true }
            if skip { for j in r { info[j].typoOK = false } }
        }
        for j in 0..<n {
            let c = target[j]
            if c == "\n" || c == "\t" { info[j].typoOK = false; continue }
            if s.bool(K.typoSkipNonLatin) && KeyLayout.info(c) == nil { info[j].typoOK = false }
        }
    }

    private func tokenSkipsTypos(_ token: String) -> Bool {
        let lower = token.lowercased()
        if s.bool(K.typoSkipURLs) {
            if lower.contains("://") || lower.hasPrefix("www.") { return true }
            let trimmed = lower.trimmingCharacters(in: .punctuationCharacters)
            let tlds = [".com", ".org", ".net", ".edu", ".gov", ".io", ".co", ".dev", ".app", ".ai", ".us", ".uk"]
            if trimmed.contains(".") && tlds.contains(where: { trimmed.hasSuffix($0) || trimmed.contains($0 + "/") }) { return true }
        }
        if s.bool(K.typoSkipEmails) && token.contains("@") && token.contains(".") { return true }
        if s.bool(K.typoSkipNumbers) && token.contains(where: \.isNumber) && token.filter(\.isLetter).count <= 2 { return true }
        if s.bool(K.typoSkipCode) {
            let codeChars: Set<Character> = ["_", "{", "}", "=", "<", ">", "\\", "|", "`", "$", "^", "~", "#", "*"]
            if token.contains(where: { codeChars.contains($0) }) { return true }
            if token.contains("()") || token.contains("[]") || token.contains("->") || token.contains("::") || token.contains("//") { return true }
            // camelCase
            let chars = Array(token)
            if chars.count > 2 {
                for q in 1..<chars.count where chars[q].isUppercase && chars[q - 1].isLowercase { return true }
            }
            // dotted identifiers like obj.method (but not e.g. or end of sentence)
            if let dot = chars.firstIndex(of: "."), dot > 0, dot < chars.count - 1,
               chars[dot - 1].isLetter, chars[dot + 1].isLetter, chars.filter({ $0 == "." }).count == 1,
               chars.count > 4 { return true }
        }
        return false
    }

    private func isSentenceStart(_ idx: Int) -> Bool {
        var j = idx - 1
        while j >= 0 && (target[j] == " " || target[j] == "\t" || target[j] == "\"" || target[j] == "“" || target[j] == "(") { j -= 1 }
        if j < 0 { return true }
        return [".", "!", "?", "\n"].contains(target[j])
    }

    private func isParagraphStart(_ idx: Int) -> Bool {
        var j = idx - 1
        var newlines = 0
        while j >= 0 && target[j].isWhitespace { if target[j] == "\n" { newlines += 1 }; j -= 1 }
        return j < 0 || newlines >= 2 || (newlines >= 1 && code)
    }

    // MARK: Run

    private mutating func run() -> TypingPlan {
        while i < n || pending != nil {
            if let p = pending {
                let mustResolve = p.remaining <= 0 || i >= n || target[i] == "\n" || (safe && !Self.isWordChar(target[i]))
                    || isGuardedSpaceRun(at: i)
                if mustResolve { resolvePending(); continue }
            }
            let wid = info[i].wordId
            if wid >= 0 && info[i].posInWord == 0 { wordStartEvents(i, wid) }
            if pending == nil, typosOn, tryTypo() { continue }
            typeTarget()
            if pending != nil { pending!.remaining -= 1 }
            charsSinceTypo += 1
        }
        if s.bool(K.proofreadAtEnd) && !unfixed.isEmpty { proofread() }

        var plan = TypingPlan(steps: steps, target: target, finalModel: buffer,
                              unfixedLeft: unfixed.count, typoCount: typoCount)
        if s.str(K.speedMode) == "timer" { applyTimer(&plan) }
        capHolds(&plan)
        return plan
    }

    // MARK: Emitting

    private var progressNow: Int { progressOverride ?? (pending?.targetStart ?? i) }

    private mutating func emit(_ a: KeyAction, _ keyDelay: Double, extraPause: Double = 0) {
        let pause = max(0, carryPause + extraPause)
        carryPause = 0
        let hold = rng.range(s.ms(K.holdMin), s.ms(K.holdMax))
        steps.append(Step(action: a, keyDelay: max(0, keyDelay), pauseDelay: pause, hold: hold,
                          group: currentGroup, progress: progressNow))
        elapsed += keyDelay + pause
    }

    private func action(for c: Character) -> KeyAction {
        switch c {
        case "\n": return .newline
        case "\t": return .tab
        default: return .char(c)
        }
    }

    /// Emit a character key press (does not touch the text model).
    private mutating func pressChar(_ c: Character, targetIdx: Int?, slow: Double = 1) {
        let d = charDelay(c, targetIdx: targetIdx) * slow
        emit(action(for: c), d)
        prevChar = c
        prevKey = keyInfo(c)
    }

    private func keyInfo(_ c: Character) -> KeyInfo? {
        if c == "\n" { return KeyInfo(keyCode: 36, shift: false, base: "\n", row: 2, x: 12.75, finger: 7) }
        if c == "\t" { return KeyInfo(keyCode: 48, shift: false, base: "\t", row: 1, x: 0, finger: 0) }
        return KeyLayout.info(c)
    }

    /// Two+ spaces right after a non-space: macOS would turn the first two into ". ".
    private func isGuardedSpaceRun(at idx: Int) -> Bool {
        guard spaceGuard, idx + 1 < n, target[idx] == " ", target[idx + 1] == " " else { return false }
        guard let last = buffer.last else { return false }
        return !last.isWhitespace
    }

    /// Type a run of spaces without triggering "double-space → period": type one space, then insert each
    /// extra space *before* it (← then space), so the character before the cursor is never a space.
    private mutating func typeGuardedSpaceRun() {
        var k = 0
        while i + k < n && target[i + k] == " " { k += 1 }
        let startIdx = i
        pressChar(" ", targetIdx: startIdx)
        for _ in 1..<k {
            emit(.left, arrowDelay())
            pressChar(" ", targetIdx: startIdx)
        }
        for _ in 1..<k { emit(.right, arrowDelay()) }
        buffer.append(contentsOf: Array(repeating: " ", count: k))
        i += k
        carryPause += pauseAfter(" ", at: i - 1)
    }

    private mutating func typeTarget() {
        if isGuardedSpaceRun(at: i) { typeGuardedSpaceRun(); return }
        let c = target[i]
        if i == hesitationAt { carryPause += rng.range(s.ms(K.hesitationMin), s.ms(K.hesitationMax)) }
        pressChar(c, targetIdx: i)
        buffer.append(c)
        let idx = i
        i += 1
        if code && c == "\n" && s.str(K.codeIndentMode) == "clear" {
            emit(.codeIndentSelect, baseInterval * 1.3)
            emit(.deleteSelection, baseInterval)
        }
        if code && s.str(K.codeAutoCloseMode) == "forwardDelete" && "([{\"'`".contains(c) {
            emit(.forwardDelete, baseInterval * 0.6)
        }
        carryPause += pauseAfter(c, at: idx)
    }

    // MARK: Timing

    private var fatigueFraction: Double {
        let maxF = s.pct(K.fatigueMax)
        guard maxF > 0 else { return 0 }
        return min(1, (s.pct(K.fatiguePerMinute) * elapsed / 60) / maxF)
    }

    private mutating func charDelay(_ c: Character, targetIdx: Int?) -> Double {
        var mult = rng.variation(s.pct(K.variation), distribution: dist)
        var bursting = false
        if let k = keyInfo(c) {
            mult *= s.pct(K.finger(k.finger)) * s.pct(K.row(min(4, k.row)))
            if k.shift {
                mult *= 1 + s.pct(K.shiftPenalty)
                if c.isUppercase && (prevChar == nil || prevChar!.isWhitespace) { mult *= 1 + s.pct(K.capitalAfterSpace) }
            }
            if k.row == 0 { mult *= 1 + s.pct(K.numberRowPenalty) }
            if !c.isLetter && !c.isNumber && !c.isWhitespace { mult *= 1 + s.pct(K.symbolPenalty) }
            if let p = prevKey {
                if p.keyCode == k.keyCode { mult *= s.pct(K.sameKeyRepeat) }
                else if p.finger == k.finger && k.finger != 8 { mult *= 1 + s.pct(K.sameFingerPenalty) }
                else if p.hand != k.hand && p.hand != 2 && k.hand != 2 { mult *= 1 - s.pct(K.handAlternation) }
                if k.row < 4 && p.row < 4 { mult *= 1 + s.pct(K.rowJumpPenalty) * Double(abs(p.row - k.row)) }
            }
        } else {
            mult *= 1 + s.pct(K.unicodePenalty)
        }
        if let pc = prevChar, pc.isLetter, c.isLetter {
            let bg = (String(pc) + String(c)).lowercased()
            if words.bigrams.contains(bg) && rng.chance(s.pct(K.bigramBurstChance)) {
                mult *= s.pct(K.bigramBurst); bursting = true
            }
        }
        if let idx = targetIdx, idx < n {
            let inf = info[idx]
            if inf.wordId >= 0 {
                if wordBurstActive { mult *= s.pct(K.wordBurst); bursting = true }
                if inf.posInWord == 0 { mult *= 1 + s.pct(K.wordStartMult) }
                if capsWord[inf.wordId] { mult *= 1 + s.pct(K.capsWordSlowdown) }
            }
            if c.isNumber { mult *= 1 + s.pct(K.numberSlowdown) }
        }
        if burstLeft > 0 { mult *= s.pct(K.randomBurstMult); burstLeft -= 1; bursting = true }
        let warm = s.num(K.warmupSeconds)
        if warm > 0 && elapsed < warm { mult *= 1 + (s.pct(K.warmupMult) - 1) * (1 - elapsed / warm) }
        mult *= 1 + min(s.pct(K.fatigueMax), s.pct(K.fatiguePerMinute) * elapsed / 60)
        let period = max(1, s.num(K.driftPeriod))
        mult *= 1 + s.pct(K.driftAmount) * sin(2 * .pi * elapsed / period + driftPhase)
        lastWasBurst = bursting
        let d = baseInterval * max(0.05, mult)
        return min(max(d, s.ms(K.minKeyDelay)), max(s.ms(K.minKeyDelay), s.ms(K.maxKeyDelay)))
    }

    private mutating func backspaceDelay() -> Double {
        let d = baseInterval * s.pct(K.backspaceSpeed) * rng.variation(s.pct(K.backspaceVariation), distribution: dist)
        return max(d, s.ms(K.minKeyDelay) * 0.6)
    }

    private mutating func arrowDelay() -> Double {
        max(0.012, baseInterval * s.pct(K.arrowSpeed) * rng.variation(0.25, distribution: dist))
    }

    private mutating func jitter(_ v: Double) -> Double {
        guard v > 0 else { return 0 }
        return v * max(0.1, 1 + rng.normal() * s.pct(K.pauseJitter) * 0.6)
    }

    private mutating func pauseAfter(_ c: Character, at idx: Int) -> Double {
        let next: Character? = idx + 1 < n ? target[idx + 1] : nil
        let nextIsBreak = next == nil || next!.isWhitespace
        var base = 0.0
        switch c {
        case " ": base = s.ms(K.pauseSpace)
        case ",": base = s.ms(K.pauseComma)
        case ".": if nextIsBreak { base = s.ms(K.pausePeriod) }
        case "?", "!": if nextIsBreak { base = s.ms(K.pauseQuestion) }
        case ":", ";": base = s.ms(K.pauseColon)
        case "–", "—": base = s.ms(K.pauseDash)
        case "-": if nextIsBreak || (idx > 0 && target[idx - 1] == " ") { base = s.ms(K.pauseDash) }
        case "\"", "”", "’", "'": if nextIsBreak || (next.map { $0.isPunctuation } ?? true) { base = s.ms(K.pauseQuote) }
        case ")", "]", "}": base = s.ms(K.pauseBracket)
        case "\n": base = (idx > 0 && target[idx - 1] == "\n") ? s.ms(K.pauseParagraph) : s.ms(K.pauseNewline)
        default: break
        }
        var total = jitter(base)
        if (c == "." || c == "?" || c == "!") && nextIsBreak && rng.chance(s.pct(K.rereadChance)) {
            total += rng.range(s.num(K.rereadMin), s.num(K.rereadMax))
        }
        return total
    }

    private mutating func wordStartEvents(_ idx: Int, _ wid: Int) {
        let w = wordStrings[wid]
        let len = wordRanges[wid].count
        typosInWord = 0
        wordBurstActive = words.common.contains(w) && rng.chance(s.pct(K.wordBurstChance))
        if burstLeft <= 0 && rng.chance(s.pct(K.randomBurstChance)) {
            let L = Double(max(2, s.int(K.randomBurstLength)))
            burstLeft = max(2, Int(L * rng.range(0.7, 1.3)))
        }
        if s.bool(K.thinkEnabled) {
            let p: Double
            if isParagraphStart(idx) { p = s.pct(K.thinkChanceParagraph) }
            else if isSentenceStart(idx) { p = s.pct(K.thinkChanceSentence) }
            else { p = s.pct(K.thinkChanceWord) }
            if rng.chance(p) {
                let lo = s.num(K.thinkMin), hi = max(lo, s.num(K.thinkMax))
                carryPause += lo + (hi - lo) * pow(rng.double(), 1.6)
            }
        }
        if len >= s.int(K.longWordLength) { carryPause += s.ms(K.longWordPause) * rng.range(0.6, 1.4) }
        if len >= 4 && !words.common.contains(w) && w.allSatisfy(\.isLetter) && rng.chance(s.pct(K.rareWordChance)) {
            carryPause += s.ms(K.rareWordPause) * rng.range(0.6, 1.4)
        }
        hesitationAt = (len >= 3 && rng.chance(s.pct(K.hesitationChance))) ? idx + rng.int(1, len - 1) : -1
        if s.bool(K.breakEnabled) {
            let minute = Int(elapsed / 60)
            while lastMinuteChecked < minute {
                lastMinuteChecked += 1
                if rng.chance(s.pct(K.breakChancePerMinute)) && elapsed - lastBreakAt >= s.num(K.breakMinGap) * 60 {
                    carryPause += rng.range(s.num(K.breakMin), s.num(K.breakMax))
                    lastBreakAt = elapsed
                }
            }
        }
    }

    // MARK: Typos

    private func wordRemaining(from idx: Int, wordId: Int) -> Int {
        guard wordId >= 0 else { return 0 }
        return max(0, wordRanges[wordId].upperBound - idx)
    }

    private func lineRemaining(from idx: Int) -> Int {
        var j = idx
        while j < n && target[j] != "\n" { j += 1 }
        return j - idx
    }

    private func neighborChar(_ c: Character) -> Character? {
        let (direct, diag) = KeyLayout.neighbors(of: c)
        var pool: [(Character, Double)] = direct.map { ($0, 1.0) } + diag.map { ($0, s.pct(K.typoDiagonalWeight)) }
        if c.isLetter {
            let letters = pool.filter { $0.0.isLetter }
            if !letters.isEmpty { pool = letters }
        }
        guard !pool.isEmpty else { return nil }
        var r = rng
        let idx = r.weighted(pool.map(\.1))
        return pool[idx].0
    }

    /// Returns true if a typo was made at `i`.
    private mutating func tryTypo() -> Bool {
        let inf = info[i]
        guard inf.typoOK, charsSinceTypo >= s.int(K.typoMinGap), typosInWord < s.int(K.typoMaxPerWord) else { return false }
        let c = target[i]
        let master = s.pct(K.typoMaster)
        let wid = inf.wordId

        // Word-level typos at word start
        if wid >= 0 && inf.posInWord == 0 {
            let r = wordRanges[wid]
            let wholeOK = r.allSatisfy { info[$0].typoOK }
            if wholeOK {
                let w = wordStrings[wid]
                if let variants = words.misspellings[w], !capsWord[wid],
                   rng.chance(min(1, s.pct(K.typoMisspell) * master)), var wrong = rng.pick(variants) {
                    if target[r.lowerBound].isUppercase, let f = wrong.first {
                        wrong = f.uppercased() + wrong.dropFirst()
                    }
                    makeTypo(wrong: Array(wrong), consumed: r.count, forceImmediate: false)
                    return true
                }
                if r.count >= 3, rng.chance(s.pct(K.typoWrongWord) * master),
                   let other = WordData.shared.similarWord(to: w, rng: &rng) {
                    var wrong = Array(other)
                    let m = rng.int(2, wrong.count)
                    wrong = Array(wrong.prefix(m))
                    if target[r.lowerBound].isUppercase, let f = wrong.first { wrong[0] = Character(f.uppercased()) }
                    let correctPrefix = Array(target[r.lowerBound..<min(r.upperBound, r.lowerBound + wrong.count)])
                    if wrong != correctPrefix {
                        makeTypo(wrong: wrong, consumed: r.count, forceImmediate: true)
                        return true
                    }
                }
            }
        }

        // Character-level typos
        var mult = master
        if wid >= 0 {
            let len = wordRanges[wid].count
            if inf.posInWord == 0 { mult *= s.pct(K.typoWordStartMult) }
            if inf.posInWord == len - 1 { mult *= s.pct(K.typoWordEndMult) }
            if len >= s.int(K.longWordLength) { mult *= s.pct(K.typoLongWordMult) }
        }
        if lastWasBurst { mult *= s.pct(K.typoBurstMult) }
        mult *= 1 + s.pct(K.typoFatigueMult) * fatigueFraction

        let nextSameWord = i + 1 < n && info[i + 1].wordId == wid && wid >= 0 && target[i + 1].isLetter && info[i + 1].typoOK
        var cands: [(TypoKind, Double)] = []
        if c.isLetter {
            if neighborChar(c) != nil { cands.append((.neighbor, s.pct(K.typoNeighbor))) }
            if nextSameWord && target[i + 1] != c { cands.append((.transpose, s.pct(K.typoTranspose))) }
            cands.append((.double, s.pct(K.typoDouble)))
            if nextSameWord && inf.posInWord > 0 { cands.append((.skip, s.pct(K.typoSkip))) }
            if c.isUppercase || inf.posInWord == 0 { cands.append((.shift, s.pct(K.typoShift))) }
            if inf.posInWord == 0 && c.isUppercase && nextSameWord && target[i + 1].isLowercase {
                cands.append((.shiftHold, s.pct(K.typoShiftHold)))
            }
            if neighborChar(c) != nil { cands.append((.fatFinger, s.pct(K.typoFatFinger))) }
            if KeyLayout.mirror(of: c) != nil { cands.append((.mirror, s.pct(K.typoMirror))) }
        } else if c == " " && !safe && !spaceGuard, i > 0, i + 1 < n, target[i - 1].isLetter, target[i + 1].isLetter,
                  info[i - 1].typoOK, info[i + 1].typoOK {
            cands.append((.space, s.pct(K.typoSpace)))
        } else if ",./;'[]".contains(c), neighborChar(c) != nil {
            cands.append((.punct, s.pct(K.typoPunct)))
        }
        guard !cands.isEmpty else { return false }
        let total = cands.reduce(0) { $0 + $1.1 } * mult
        guard rng.chance(min(0.9, total)) else { return false }
        let kind = cands[rng.weighted(cands.map(\.1))].0

        switch kind {
        case .neighbor, .punct:
            guard let nb = neighborChar(c) else { return false }
            makeTypo(wrong: [nb], consumed: 1)
        case .transpose:
            makeTypo(wrong: [target[i + 1], c], consumed: 2)
        case .double:
            makeTypo(wrong: [c, c], consumed: 1)
        case .skip:
            makeTypo(wrong: [target[i + 1]], consumed: 2)
        case .shift:
            let swapped = c.isUppercase ? Character(c.lowercased()) : Character(c.uppercased())
            makeTypo(wrong: [swapped], consumed: 1)
        case .shiftHold:
            makeTypo(wrong: [c, Character(target[i + 1].uppercased())], consumed: 2)
        case .fatFinger:
            guard let nb = neighborChar(c) else { return false }
            makeTypo(wrong: rng.chance(0.5) ? [c, nb] : [nb, c], consumed: 1)
        case .mirror:
            guard let m = KeyLayout.mirror(of: c) else { return false }
            makeTypo(wrong: [m], consumed: 1)
        case .space:
            if rng.chance(0.5) { makeTypo(wrong: [" ", " "], consumed: 1) }
            else { makeTypo(wrong: [target[i + 1]], consumed: 2) }
        }
        return true
    }

    private mutating func makeTypo(wrong: [Character], consumed: Int, forceImmediate: Bool = false) {
        let startBuf = buffer.count
        let targetStart = i
        let wid = info[i].wordId
        groupCounter += 1
        currentGroup = groupCounter
        progressOverride = targetStart
        for ch in wrong {
            pressChar(ch, targetIdx: nil)
            buffer.append(ch)
        }
        progressOverride = nil
        let correct = Array(target[i..<min(n, i + consumed)])
        i = min(n, i + consumed)
        typoCount += 1
        typosInWord += 1
        charsSinceTypo = 0

        let allowLate = !safe && !code
        if allowLate && !forceImmediate && rng.chance(s.pct(K.leaveUnfixed)) {
            unfixed.append(Unfixed(startBuf: startBuf, wrong: wrong, correct: correct))
            currentGroup = -1
            return
        }

        let lineRem = lineRemaining(from: i)
        let wordRem = wordRemaining(from: i, wordId: wid)
        var mode: FixMode = .immediate
        if !forceImmediate {
            var weights = [s.num(K.fixImmediateWeight), s.num(K.fixDelayedWeight),
                           s.num(K.fixEndOfWordWeight), allowLate ? s.num(K.fixLateWeight) : 0]
            if weights.allSatisfy({ $0 <= 0 }) { weights[0] = 1 }
            mode = [FixMode.immediate, .delayed, .endOfWord, .late][rng.weighted(weights)]
        }
        var remaining: Int
        switch mode {
        case .immediate: remaining = 0
        case .delayed: remaining = rng.int(s.int(K.fixDelayedMin), max(s.int(K.fixDelayedMin), s.int(K.fixDelayedMax)))
        case .endOfWord: remaining = wordRem
        case .late: remaining = rng.int(s.int(K.fixLateMin), max(s.int(K.fixLateMin), s.int(K.fixLateMax)))
        }
        remaining = min(remaining, lineRem)
        if safe { remaining = min(remaining, wordRem) }
        pending = Pending(startBuf: startBuf, wrong: wrong, correct: correct,
                          targetStart: targetStart, mode: mode, remaining: remaining)
    }

    private static func commonPrefix(_ a: [Character], _ b: [Character]) -> Int {
        var k = 0
        while k < a.count && k < b.count && a[k] == b[k] { k += 1 }
        return k
    }

    /// Lowest buffer index a backspace fix may reach (line start / after unfixed typos).
    private func deleteFloor(before pos: Int) -> Int {
        var j = pos - 1
        while j >= 0 && buffer[j] != "\n" { j -= 1 }
        var floor = j + 1
        if let u = unfixed.last { floor = max(floor, u.startBuf + u.wrong.count) }
        return floor
    }

    private mutating func resolvePending() {
        guard let p = pending else { return }
        pending = nil
        progressOverride = p.targetStart
        let wrongEnd = p.startBuf + p.wrong.count
        let k = buffer.count - wrongEnd
        let prefix = Self.commonPrefix(p.wrong, p.correct)
        carryPause += rng.range(s.ms(K.noticeMin), max(s.ms(K.noticeMin), s.ms(K.noticeMax)))
        let slow = 1 + s.pct(K.retypeSlowdown)

        if p.mode == .late && k > 0 {
            for _ in 0..<k { emit(.left, arrowDelay()) }
            for _ in 0..<(p.wrong.count - prefix) { emit(.backspace, backspaceDelay()) }
            for ch in p.correct[prefix...] { pressChar(ch, targetIdx: nil, slow: slow) }
            buffer.replaceSubrange(p.startBuf..<wrongEnd, with: p.correct)
            // Arrow keys only: ⌘→ jumps to the end of the *visible* line, which breaks in wrapped text.
            for _ in 0..<k { emit(.right, arrowDelay()) }
        } else {
            let floor = deleteFloor(before: p.startBuf)
            var delFrom = p.startBuf + prefix
            if rng.chance(s.pct(K.overDeleteChance)) {
                delFrom = max(floor, delFrom - rng.int(1, max(1, s.int(K.overDeleteMax))))
            }
            // Option-Backspace: delete back to the start of the current word in one press.
            var useWordDelete = false
            if rng.chance(s.pct(K.wordDeleteChance)) {
                var ws = buffer.count
                while ws > floor && !buffer[ws - 1].isWhitespace { ws -= 1 }
                let region = buffer[ws..<buffer.count]
                if ws <= p.startBuf + prefix, region.count >= s.int(K.wordDeleteMinChars),
                   region.allSatisfy({ $0.isLetter }), ws >= floor {
                    delFrom = ws
                    useWordDelete = true
                }
            }
            let retype = Array(buffer[delFrom..<(p.startBuf + prefix)]) + Array(p.correct[prefix...]) + Array(buffer[wrongEnd..<buffer.count])
            if useWordDelete {
                emit(.optionBackspace, backspaceDelay() * 1.5)
                buffer.removeSubrange(delFrom..<buffer.count)
            } else {
                while buffer.count > delFrom {
                    emit(.backspace, backspaceDelay())
                    buffer.removeLast()
                }
            }
            for ch in retype {
                // Occasionally fumble while fixing: wrong key, notice instantly, backspace.
                if ch.isLetter, rng.chance(s.pct(K.typoWhileFixing)), let nb = neighborChar(ch) {
                    pressChar(nb, targetIdx: nil)
                    emit(.backspace, backspaceDelay(), extraPause: rng.range(0.08, 0.3))
                }
                pressChar(ch, targetIdx: nil, slow: slow)
                buffer.append(ch)
            }
        }
        progressOverride = nil
        carryPause += s.ms(K.pauseAfterFix) * rng.range(0.6, 1.4)
        currentGroup = -1
    }

    private mutating func proofread() {
        groupCounter += 1
        currentGroup = groupCounter
        progressOverride = n
        carryPause += rng.range(s.num(K.rereadMin), max(s.num(K.rereadMin), s.num(K.rereadMax)))
        let arrow = s.ms(K.proofreadArrowSpeed)
        var caret = buffer.count
        for u in unfixed.reversed() {
            let end = u.startBuf + u.wrong.count
            for _ in 0..<max(0, caret - end) { emit(.left, arrow * rng.range(0.7, 1.3)) }
            carryPause += rng.range(0.2, 0.6)
            let prefix = Self.commonPrefix(u.wrong, u.correct)
            for _ in 0..<(u.wrong.count - prefix) { emit(.backspace, backspaceDelay()) }
            for ch in u.correct[prefix...] { pressChar(ch, targetIdx: nil) }
            buffer.replaceSubrange(u.startBuf..<end, with: u.correct)
            caret = u.startBuf + u.correct.count
            carryPause += rng.range(0.15, 0.5)
        }
        for _ in 0..<max(0, buffer.count - caret) { emit(.right, arrow * rng.range(0.7, 1.3)) }
        unfixed = []
        progressOverride = nil
        currentGroup = -1
    }

    // MARK: Post-processing

    private func applyTimer(_ plan: inout TypingPlan) {
        let D = max(1, s.num(K.timerMinutes) * 60)
        let Kt = plan.steps.reduce(0) { $0 + $1.keyDelay }
        let P = plan.steps.reduce(0) { $0 + $1.pauseDelay }
        guard Kt + P > 0 else { return }
        let wpm = max(1, s.num(K.wpm))
        let minW = max(1, s.num(K.timerMinWPM)), maxW = max(minW, s.num(K.timerMaxWPM))
        func clampA(_ a: Double) -> Double {
            let eff = min(maxW, max(minW, wpm / a))
            return wpm / eff
        }
        var a = 1.0, b = 1.0
        switch s.str(K.timerScaleMode) {
        case "uniform":
            a = D / (Kt + P); b = a
        case "pauses":
            a = 1
            if P > 0 && D - Kt > 0 { b = (D - Kt) / P }
            else { b = P > 0 ? 0 : 1; a = clampA(D / max(Kt, 0.001)) }
        default:
            a = clampA(D / (Kt + P))
            b = P > 0 ? max(0, (D - a * Kt) / P) : 1
            if P == 0 { a = clampA(D / max(Kt, 0.001)) }
        }
        for j in plan.steps.indices {
            plan.steps[j].keyDelay *= a
            plan.steps[j].pauseDelay *= b
        }
    }

    private func capHolds(_ plan: inout TypingPlan) {
        guard !plan.steps.isEmpty else { return }
        for j in plan.steps.indices {
            let next = j + 1 < plan.steps.count ? plan.steps[j + 1].delay : 0.2
            plan.steps[j].hold = max(0.004, min(plan.steps[j].hold, next * 0.8))
        }
    }
}
