import Foundation

/// Replays plans against a simulated text box to prove the final text matches the clipboard.
/// Run: HW_SELFTEST=1 Handwritten.app/Contents/MacOS/Handwritten
enum SelfTest {
    static func simulate(_ steps: [Step], initial: String = "", caret startCaret: Int? = nil) -> String {
        var buf: [Character] = Array(initial)
        var caret = startCaret ?? buf.count
        for st in steps {
            switch st.action {
            case .char(let c): buf.insert(c, at: caret); caret += 1
            case .newline: buf.insert("\n", at: caret); caret += 1
            case .tab: buf.insert("\t", at: caret); caret += 1
            case .backspace: if caret > 0 { buf.remove(at: caret - 1); caret -= 1 }
            case .optionBackspace:
                var s = caret
                while s > 0 && buf[s - 1].isWhitespace { s -= 1 }
                while s > 0 && !buf[s - 1].isWhitespace && (buf[s - 1].isLetter || buf[s - 1].isNumber) { s -= 1 }
                buf.removeSubrange(s..<caret); caret = s
            case .left: caret = max(0, caret - 1)
            case .right: caret = min(buf.count, caret + 1)
            case .cmdRight:
                while caret < buf.count && buf[caret] != "\n" { caret += 1 }
            case .forwardDelete, .codeIndentSelect, .deleteSelection, .wait: break
            }
        }
        return String(buf)
    }

    @MainActor
    static func run() -> Int32 {
        let samples = [
            "The quick brown fox jumps over the lazy dog. Then it ran away, because it was definitely tired!",
            "Hello, World! I can't believe it's already February. We're going to the restaurant tomorrow at 7:30pm.",
            "Emoji test 😀👍🏽 and accents: café, naïve, jalapeño. Symbols: ≤ ≥ → ∫ ∑ — “quotes” and ‘single’.",
            "Line one\nLine two has more words in it.\n\nNew paragraph with https://example.com/path and me@mail.com inside.",
            "func hello() {\n    let x = camelCase + 42\n    print(\"hi\")\n}",
            "Two  spaces here.  And   three there.    Four now. End",
            String(repeating: "This is a longer paragraph used to stress the planner with many words and sentences. ", count: 30),
        ]
        var failures = 0, runs = 0
        let words = WordData.shared.snapshot()
        let base = SettingsStore.shared.snapshot.values
        let variants: [[String: SettingValue]] = [
            [:],
            [K.typoMaster: .number(400), K.leaveUnfixed: .number(30), K.fixLateWeight: .number(60), K.overDeleteChance: .number(60), K.wordDeleteChance: .number(60), K.typoWhileFixing: .number(40), K.typoMinGap: .number(0)],
            [K.typoMaster: .number(400), K.safeTypoMode: .bool(true), K.typoMinGap: .number(0)],
            [K.typoMaster: .number(300), K.fixLateWeight: .number(100), K.typoMinGap: .number(0)],
            [K.typoMaster: .number(400), K.typoMisspell: .number(100), K.typoWrongWord: .number(20), K.typoMinGap: .number(0)],
            [K.speedMode: .text("timer"), K.timerMinutes: .number(2)],
        ]
        for (vi, v) in variants.enumerated() {
            var vals = base
            for (k, x) in v { vals[k] = x }
            vals[K.proofreadAtEnd] = .bool(true)
            if vals[K.safeTypoMode] != .bool(true) { vals[K.autocorrectProtection] = .text("off") }
            for seed in 0..<40 {
                vals[K.useSeed] = .bool(true)
                vals[K.seed] = .number(Double(seed))
                vals[K.doubleSpaceGuard] = .text(seed % 2 == 0 ? "on" : "off")
                let snap = SettingsSnapshot(values: vals)
                for text in samples {
                    runs += 1
                    let prepared = TextPreparer.prepare(text, snap)
                    let plan = Planner.makePlan(text: prepared, settings: snap, words: words)
                    let result = simulate(plan.steps)
                    if result != prepared {
                        failures += 1
                        if failures <= 5 {
                            print("FAIL variant \(vi) seed \(seed)\nEXPECTED: \(prepared.debugDescription)\nGOT:      \(result.debugDescription)\n")
                        }
                    }
                    if vi == 5 && seed == 0 && text == samples[0] {
                        print(String(format: "Timer check: target 120s, planned %.2fs", plan.totalDuration))
                    }
                }
            }
        }
        print("Self-test: \(runs - failures)/\(runs) runs produced exactly the clipboard text.")
        let v = verifierTests() && analyzerTests()
        let e = engineTests()
        return failures == 0 && v && e ? 0 : 1
    }

    @MainActor
    static func verifierTests() -> Bool {
        let snap = SettingsStore.shared.snapshot
        struct C { let name: String; let pre: String; let actual: String; let expected: String; var trailing = ""; var expectRefuse = false; var expectMatch = false }
        let cases = [
            C(name: "typos in typed text", pre: "", actual: "Teh quick brwn fox jumpss", expected: "The quick brown fox jumps"),
            C(name: "keeps text that was already there", pre: "Existing text. ", actual: "Helo wrold", expected: "Hello world"),
            C(name: "removes auto-inserted extra brackets", pre: "", actual: "func a() {\n}\n}", expected: "func a() {\n}"),
            C(name: "restores a missing new line", pre: "", actual: "line one line two", expected: "line one\nline two"),
            C(name: "ignores smart quotes", pre: "", actual: "He said “hi” and it’s fine", expected: "He said \"hi\" and it's fine"),
            C(name: "text after the cursor is untouched", pre: "Start: ", actual: "recieve teh mail", expected: "receive the mail", trailing: " [rest of document]"),
            C(name: "copied text with a trailing line break is left alone", pre: "", actual: "The quick brown fox jumps over the lazy dog.\n", expected: "The quick brown fox jumps over the lazy dog.", expectMatch: true),
            C(name: "trailing line break + a real typo: fixes only the typo", pre: "", actual: "The quick brwn fox jumps over the lazy dog.\n", expected: "The quick brown fox jumps over the lazy dog.", trailing: ""),
            C(name: "refuses when cursor clearly moved", pre: "", actual: "completely different words here", expected: "The quick brown fox jumps", expectRefuse: true),
        ]
        var ok = true
        for c in cases {
            let full = c.pre + c.actual + c.trailing
            var caret = (c.pre + c.actual).count
            if c.actual.hasSuffix("\n") && c.trailing.isEmpty { caret -= 1 } // apps keep the cursor before the final line break
            let result = Verifier.plan(expected: c.expected, actual: full, caret: c.trailing.isEmpty ? nil : caret, settings: snap)
            var pass = false
            var got = ""
            switch result {
            case .match: got = full; pass = !c.expectRefuse && (c.expectMatch || c.actual == c.expected || c.name.contains("smart"))
            case .refuse(let n): got = "refused (\(n) edits)"; pass = c.expectRefuse
            case .fix(let steps, _):
                got = simulate(steps, initial: full, caret: caret)
                let want = c.pre + c.expected + (c.actual.hasSuffix("\n") ? "\n" : "") + c.trailing
                pass = !c.expectRefuse && !c.expectMatch && got == want
            }
            print("\(pass ? "PASS" : "FAIL")  End check: \(c.name)\(pass ? "" : " → \(got.debugDescription)")")
            ok = ok && pass
        }
        return ok
    }

    /// Round trip: the app "types" a sample with known settings, the analyzer learns from it,
    /// and it should get roughly the same settings back.
    @MainActor
    static func analyzerTests() -> Bool {
        // A longer text (all built-in samples) so the statistics aren't decided by one or two sentences.
        let sample = PersonalizeModel.samples.map(\.text).joined(separator: " ")
        let words = WordData.shared.snapshot()
        let profiles: [(String, [String: Double])] = [
            ("slow & sloppy", [K.wpm: 35, K.pausePeriod: 900, K.pauseQuestion: 900, K.typoMaster: 200, K.pauseComma: 400]),
            ("average", [K.wpm: 60, K.pausePeriod: 500, K.pauseQuestion: 500, K.typoMaster: 100, K.pauseComma: 220]),
            ("fast & clean", [K.wpm: 95, K.pausePeriod: 250, K.pauseQuestion: 250, K.typoMaster: 40, K.pauseComma: 120]),
        ]
        var ok = true
        for (name, known) in profiles {
            var vals = SettingsStore.shared.snapshot.values
            for d in SettingsRegistry.all where Preset.typingTabs.contains(d.tab) { vals[d.key] = d.defaultValue }
            for (k, x) in known { vals[k] = .number(x) }
            vals[K.useSeed] = .bool(true); vals[K.seed] = .number(3)
            vals[K.autocorrectProtection] = .text("off"); vals[K.thinkEnabled] = .bool(false)
            vals[K.leaveUnfixed] = .number(0)
            let snap = SettingsSnapshot(values: vals)
            let plan = Planner.makePlan(text: sample, settings: snap, words: words)
            let keys = TypingAnalyzer.keys(from: plan)
            if ProcessInfo.processInfo.environment["HW_DEBUG_GAPS"] != nil {
                for j in 1..<keys.count {
                    if case .char(let c) = keys[j - 1].kind, ".!?".contains(c) {
                        print("   gap after \(c): \(String(format: "%.3f", keys[j].time - keys[j - 1].time)) → \(keys[j].kind)  step pause \(String(format: "%.3f", plan.steps[j].pauseDelay)) key \(String(format: "%.3f", plan.steps[j].keyDelay))")
                    }
                }
            }
            let a = TypingAnalyzer.analyze(keys: keys, sample: sample, finalText: String(plan.finalModel), base: snap, words: words)
            func got(_ k: String) -> Double { a.values[k]?.number ?? -1 }
            func near(_ k: String, _ tol: Double) -> Bool {
                let want = known[k]!, g = got(k)
                return abs(g - want) <= want * tol
            }
            let wpmOK = near(K.wpm, 0.15), periodOK = near(K.pausePeriod, 0.3), commaOK = near(K.pauseComma, 0.3), typoOK = near(K.typoMaster, 0.35)
            let pass = wpmOK && periodOK && commaOK && typoOK
            print(String(format: "%@  Personalize round trip (%@): WPM %.0f→%.0f, period %.0f→%.0f ms, comma %.0f→%.0f ms, typos %.0f→%.0f%%",
                         pass ? "PASS" : "FAIL", name, known[K.wpm]!, got(K.wpm), known[K.pausePeriod]!, got(K.pausePeriod),
                         known[K.pauseComma]!, got(K.pauseComma), known[K.typoMaster]!, got(K.typoMaster)))
            ok = ok && pass
        }
        return ok
    }

    /// Runs the real engine thread with keys turned off, to check timing and pause/resume.
    @MainActor
    static func engineTests() -> Bool {
        var vals = SettingsStore.shared.snapshot.values
        vals[K.dryRun] = .bool(true)
        vals[K.useSeed] = .bool(true)
        vals[K.speedMode] = .text("timer")
        vals[K.timerMinutes] = .number(3.0 / 60.0)
        let snap = SettingsSnapshot(values: vals)
        let plan = Planner.makePlan(text: "Timing test sentence with a few words, typed in about three seconds.",
                                    settings: snap, words: WordData.shared.snapshot())
        var ok = true

        let e1 = TypingEngine()
        e1.configure(snap)
        var t0 = Date()
        e1.start(plan)
        while e1.isRunning { Thread.sleep(forTimeInterval: 0.01) }
        let took = Date().timeIntervalSince(t0)
        let pass1 = abs(took - plan.totalDuration) < 0.25
        print(String(format: "%@  Engine timing: planned %.2fs, took %.2fs", pass1 ? "PASS" : "FAIL", plan.totalDuration, took))
        ok = ok && pass1

        let e2 = TypingEngine()
        e2.configure(snap)
        t0 = Date()
        e2.start(plan)
        Thread.sleep(forTimeInterval: 1.0)
        e2.requestPause()
        Thread.sleep(forTimeInterval: 0.1)
        let r1 = e2.remainingSeconds()
        Thread.sleep(forTimeInterval: 1.0)
        let r2 = e2.remainingSeconds()
        let frozen = r1 == r2
        e2.resume()
        while e2.isRunning { Thread.sleep(forTimeInterval: 0.01) }
        let took2 = Date().timeIntervalSince(t0)
        let pass2 = frozen && abs(took2 - (plan.totalDuration + 1.1)) < 0.35
        print(String(format: "%@  Engine pause/resume: nothing ran while paused (%@), total %.2fs (expected ≈ %.2fs)",
                     pass2 ? "PASS" : "FAIL", frozen ? "yes" : "no", took2, plan.totalDuration + 1.1))
        ok = ok && pass2

        let e3 = TypingEngine()
        e3.configure(snap)
        e3.start(plan)
        Thread.sleep(forTimeInterval: 0.5)
        e3.stop()
        Thread.sleep(forTimeInterval: 0.1)
        let pass3 = !e3.isRunning
        print("\(pass3 ? "PASS" : "FAIL")  Engine stop is immediate")
        ok = ok && pass3

        let e4 = TypingEngine()
        e4.configure(snap)
        e4.start(plan)
        Thread.sleep(forTimeInterval: 0.5)
        e4.requestPause()
        Thread.sleep(forTimeInterval: 0.2)
        e4.stop()
        Thread.sleep(forTimeInterval: 0.1)
        let pass4 = !e4.isRunning
        print("\(pass4 ? "PASS" : "FAIL")  Stop works while paused")
        ok = ok && pass4
        return ok
    }
}
