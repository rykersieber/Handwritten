import AppKit
import ApplicationServices

/// End-of-run check: read what's actually in the text box, compare, and fix differences.
enum Verifier {
    enum FixPlan {
        case match
        case refuse(edits: Int)
        case fix(steps: [Step], edits: Int)
    }

    /// Runs on a background thread. Returns a status message.
    static func verifyAndFix(expected: String, settings s: SettingsSnapshot, engine: TypingEngine) -> String {
        let method = s.str(K.verifyMethod)
        var actual: String?
        var caretOffset: Int?   // in Characters, from AX

        if method == "auto" || method == "ax" {
            if let r = readViaAccessibility() { actual = r.text; caretOffset = r.caret }
        }
        var usedCopy = false
        if actual == nil && (method == "auto" || method == "copy") {
            actual = readViaCopy(engine: engine, restore: s.bool(K.restoreClipboardAfter))
            usedCopy = true
        }
        guard let actualText = actual else { return "Done (couldn't read the text box to check it)" }

        switch plan(expected: expected, actual: actualText, caret: caretOffset, settings: s) {
        case .match:
            return usedCopy ? "Done ✓ (checked)" : "Done ✓ (verified)"
        case .refuse(let edits):
            return "Done (found \(edits) differences; didn't fix them in case the cursor moved)"
        case .fix(let steps, let edits):
            engine.runSteps(steps)
            return "Done ✓ (fixed \(edits) difference\(edits == 1 ? "" : "s") at the end)"
        }
    }

    /// Pure: compare and build the keystrokes that turn `actual` into `expected`.
    /// Assumes our text ends at `caret` (or the end of the document) and the caret is there.
    static func plan(expected: String, actual actualText: String, caret caretOffset: Int?, settings s: SettingsSnapshot) -> FixPlan {
        let normalize = s.bool(K.verifyIgnoreSmartQuotes)
        let expOriginal = Array(expected)
        let exp = expOriginal.map { norm($0, normalize) }
        let all = Array(actualText).map { norm($0, normalize) }
        var end = min(all.count, caretOffset ?? all.count)
        // Many apps (Word, Docs, Pages, Notes) add a final line break the cursor can't move past,
        // and select-all + copy includes it. Never treat extra trailing whitespace as ours to delete:
        // the cursor sits before it, so a backspace would delete real text instead.
        let isBlank: (Character) -> Bool = { $0 == "\n" || $0 == " " || $0 == "\t" }
        let expTrailing = exp.reversed().prefix(while: isBlank).count
        var actTrailing = 0
        while actTrailing < end && isBlank(all[end - 1 - actTrailing]) { actTrailing += 1 }
        if actTrailing > expTrailing { end -= actTrailing - expTrailing }
        let maxFixes = s.int(K.verifyMaxFixes)
        let windowLen = min(end, exp.count + maxFixes)
        let window = Array(all[(end - windowLen)..<end])

        if window.count >= exp.count && window.suffix(exp.count).elementsEqual(exp) { return .match }

        guard let (removedSet, insertedSet, leadCount) = align(exp: exp, window: window) else { return .refuse(edits: exp.count) }
        var removed = removedSet
        let inserted = insertedSet
        let lead = leadCount
        removed = removed.filter { $0 >= lead }

        let edits = removed.count + inserted.count
        if edits == 0 { return .match }
        let similarity = 1 - Double(inserted.count) / Double(max(exp.count, 1))
        if edits > maxFixes || similarity < s.pct(K.verifyMinSimilarity) { return .refuse(edits: edits) }

        // Group into operations in window coordinates: at window position `pos`, delete `del`, insert `ins`.
        struct Op { var pos: Int; var del: Int; var ins: [Character] }
        var ops: [Op] = []
        var i = lead, j = 0
        while i < window.count || j < exp.count {
            if i < window.count && removed.contains(i) {
                if let last = ops.last, last.pos + last.del == i, last.ins.isEmpty { ops[ops.count - 1].del += 1 }
                else { ops.append(Op(pos: i, del: 1, ins: [])) }
                i += 1
            } else if j < exp.count && inserted.contains(j) {
                if let last = ops.last, last.pos + last.del == i { ops[ops.count - 1].ins.append(expOriginal[j]) }
                else { ops.append(Op(pos: i, del: 0, ins: [expOriginal[j]])) }
                j += 1
            } else {
                i += 1; j += 1
            }
        }

        var rng = RNG()
        let wpm = max(1, s.num(K.wpm))
        let base = 60.0 / (wpm * 5.0) * s.pct(K.verifySpeed)
        let arrow = s.ms(K.proofreadArrowSpeed)
        var steps: [Step] = []
        func add(_ a: KeyAction, _ d: Double) {
            steps.append(Step(action: a, keyDelay: d, pauseDelay: 0, hold: min(0.04, d * 0.6), group: -1, progress: 0))
        }
        var caret = window.count
        var finalLen = window.count
        for op in ops.reversed() {
            let endOfDel = op.pos + op.del
            for _ in 0..<max(0, caret - endOfDel) { add(.left, arrow * rng.range(0.7, 1.3)) }
            if let last = steps.indices.last { steps[last].pauseDelay += rng.range(0.15, 0.4) }
            for _ in 0..<op.del { add(.backspace, base * 0.6 * rng.range(0.7, 1.3)) }
            for ch in op.ins {
                let a: KeyAction = ch == "\n" ? .newline : (ch == "\t" ? .tab : .char(ch))
                add(a, base * rng.variation(0.3, distribution: "lognormal"))
            }
            caret = op.pos + op.ins.count
            finalLen += op.ins.count - op.del
        }
        for _ in 0..<max(0, finalLen - caret) { add(.right, arrow * rng.range(0.7, 1.3)) }
        return .fix(steps: steps, edits: edits)
    }

    /// Alignment of `exp` against the end of `window`, where any amount of text before our
    /// text (pre-existing content) is free. Returns window offsets to delete, exp offsets to
    /// insert, and how many leading window characters are pre-existing.
    static func align(exp: [Character], window: [Character]) -> (Set<Int>, Set<Int>, Int)? {
        // Trim the identical tail first; most of the text usually matches.
        var tail = 0
        while tail < exp.count && tail < window.count && exp[exp.count - 1 - tail] == window[window.count - 1 - tail] { tail += 1 }
        let E = Array(exp[0..<(exp.count - tail)])
        let W = Array(window[0..<(window.count - tail)])
        let n = E.count, m = W.count
        if n == 0 { return (Set(), Set(), m) }
        guard n * m <= 25_000_000 else {
            // Very large: fall back to Myers diff with a contiguous-leading-gap rule.
            var removed = Set<Int>(), inserted = Set<Int>()
            for c in E.difference(from: W) {
                switch c {
                case .remove(let o, _, _): removed.insert(o)
                case .insert(let o, _, _): inserted.insert(o)
                }
            }
            var lead = 0
            while removed.contains(lead) { lead += 1 }
            return (removed, inserted, lead)
        }
        let cols = m + 1
        var D = [Int32](repeating: 0, count: (n + 1) * cols)
        for i in 1...n {
            D[i * cols] = Int32(i)
            for j in 1...m {
                let sub = D[(i - 1) * cols + j - 1] + (E[i - 1] == W[j - 1] ? 0 : 1)
                let del = D[i * cols + j - 1] + 1
                let ins = D[(i - 1) * cols + j] + 1
                D[i * cols + j] = min(sub, del, ins)
            }
        }
        var removed = Set<Int>(), inserted = Set<Int>()
        var i = n, j = m
        while i > 0 {
            let cur = D[i * cols + j]
            if j > 0 && E[i - 1] == W[j - 1] && cur == D[(i - 1) * cols + j - 1] { i -= 1; j -= 1 }
            else if j > 0 && cur == D[(i - 1) * cols + j - 1] + 1 { removed.insert(j - 1); inserted.insert(i - 1); i -= 1; j -= 1 }
            else if j > 0 && cur == D[i * cols + j - 1] + 1 { removed.insert(j - 1); j -= 1 }
            else { inserted.insert(i - 1); i -= 1 }
        }
        return (removed, inserted, j)
    }

    private static func norm(_ c: Character, _ on: Bool) -> Character {
        switch c {
        case "\r", "\u{2028}", "\u{2029}", "\u{0B}": return "\n"
        case "\u{00A0}": return " "
        default: break
        }
        guard on else { return c }
        switch c {
        case "“", "”", "„", "″": return "\""
        case "‘", "’", "‚", "′": return "'"
        default: return c
        }
    }

    // MARK: Reading

    static func readViaAccessibility() -> (text: String, caret: Int?)? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let el = focused else { return nil }
        let element = el as! AXUIElement
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String, !text.isEmpty, text.utf16.count < 2_000_000 else { return nil }
        var caret: Int?
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rv = rangeRef, CFGetTypeID(rv) == AXValueGetTypeID() {
            var r = CFRange()
            if AXValueGetValue(rv as! AXValue, .cfRange, &r) {
                let utf16 = Array(text.utf16)
                let loc = min(utf16.count, max(0, r.location + r.length))
                caret = String(utf16CodeUnits: Array(utf16[0..<loc]), count: loc).count
            }
        }
        return (text, caret)
    }

    /// Select all + copy, read the clipboard, restore it, and put the caret at the end.
    static func readViaCopy(engine: TypingEngine, restore: Bool) -> String? {
        let saved: [NSPasteboardItem] = DispatchQueue.main.sync {
            ClipboardManager.shared.suspendTracking = true
            return NSPasteboard.general.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
                let copy = NSPasteboardItem()
                for t in item.types { if let d = item.data(forType: t) { copy.setData(d, forType: t) } }
                return copy
            } ?? []
        }
        let before = DispatchQueue.main.sync { NSPasteboard.general.changeCount }
        let sender = engine.keySender
        sender.selectAll()
        Thread.sleep(forTimeInterval: 0.15)
        sender.copy()
        var text: String?
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.05)
            let changed = DispatchQueue.main.sync { NSPasteboard.general.changeCount != before }
            if changed { text = DispatchQueue.main.sync { NSPasteboard.general.string(forType: .string) }; break }
        }
        // Collapse the selection to the end.
        sender.perform(.right, hold: 0.02)
        Thread.sleep(forTimeInterval: 0.05)
        DispatchQueue.main.sync {
            if restore {
                NSPasteboard.general.clearContents()
                if !saved.isEmpty { NSPasteboard.general.writeObjects(saved) }
            }
            ClipboardManager.shared.ignoreCurrentChangeCount()
            ClipboardManager.shared.suspendTracking = false
        }
        return text
    }
}
