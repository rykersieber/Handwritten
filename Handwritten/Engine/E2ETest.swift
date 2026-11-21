import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Real end-to-end tests. Launch with:
///   open -n --env HW_E2E=/path/to/output/dir build/Build/Products/Debug/Handwritten.app
/// Writes results to <dir>/e2e-results.txt. Types into TextEdit — don't touch the computer while it runs.
@MainActor
enum E2ETest {
    private static var out: [String] = []
    private static var passed = 0
    private static var failed = 0
    private static var dir: URL!

    private static func log(_ s: String) {
        out.append(s)
        try? out.joined(separator: "\n").write(to: dir.appendingPathComponent("e2e-results.txt"), atomically: true, encoding: .utf8)
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if ok { passed += 1 } else { failed += 1 }
        log("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    }

    private static func sleep(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

    static func run(outputDir: String) {
        dir = URL(fileURLWithPath: outputDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Task { @MainActor in
            await runAll()
            exit(failed == 0 ? 0 : 1)
        }
    }

    private static func runAll() async {
        log("Handwritten E2E — \(Date())")
        let settingsBackup = SettingsStore.shared._testState()
        let historyBackup = ClipboardManager.shared._testSnapshot()
        let currentBackup = ClipboardManager.shared.currentText
        let pbBackup = savePasteboard()

        await sleep(1.0)
        log("Accessibility: \(AXIsProcessTrusted())  Input Monitoring: \(CGPreflightListenEventAccess())  EventTap: \(InputMonitor.shared.usingEventTap)")

        testHumanness()
        testPresets()
        testExportImport()
        testClipboard()
        testHotkeys()
        testMask()
        await testSettingsSidebar()

        if ProcessInfo.processInfo.environment["HW_E2E_SKIP_TYPING"] != nil {
            log("SKIP  real typing tests (HW_E2E_SKIP_TYPING)")
        } else if AXIsProcessTrusted() {
            await testTyping()
            await testControllerEscapeAndAutoPause()
        } else {
            log("SKIP  real typing tests (Accessibility not granted to this build)")
        }

        SettingsStore.shared._testRestore(settingsBackup)
        ClipboardManager.shared._testRestore(historyBackup, current: currentBackup)
        restorePasteboard(pbBackup)
        log("\nRESULT: \(passed) passed, \(failed) failed")
    }

    // MARK: Settings

    private static func testHumanness() {
        let s = SettingsStore.shared
        s.clearManualOverrides()
        s.set(K.humanness, 0.0)
        check("Humanness 0% → variation 0", s.num(K.variation) == 0, "got \(s.num(K.variation))")
        check("Humanness 0% → typo amount 0", s.num(K.typoMaster) == 0, "got \(s.num(K.typoMaster))")
        s.set(K.humanness, 100.0)
        check("Humanness 100% → variation 70", s.num(K.variation) == 70, "got \(s.num(K.variation))")
        s.set(K.humanness, 50.0)
        check("Humanness 50% → defaults", s.num(K.variation) == 35 && s.num(K.typoMaster) == 100,
              "variation \(s.num(K.variation)), typos \(s.num(K.typoMaster))")
        s.set(K.variation, 55.0)
        s.set(K.humanness, 0.0)
        check("Hand-set value is not moved by humanness", s.num(K.variation) == 55, "got \(s.num(K.variation))")
        s.clearManualOverrides()
        check("Clearing overrides lets slider control it", s.num(K.variation) == 0, "got \(s.num(K.variation))")
        s.set(K.humanness, 50.0)
        s.reset(K.variation)
        check("Reset returns default", s.num(K.variation) == 35 && !s.isChanged(K.variation))
        let all = SettingsRegistry.all.count
        let simple = SettingsRegistry.all.filter { $0.level == .simple }.count
        let adv = SettingsRegistry.all.filter { $0.level <= .advanced }.count
        check("Settings registry size", all >= 200, "\(simple) simple / \(adv) advanced / \(all) custom")
        let dupes = Dictionary(grouping: SettingsRegistry.all, by: \.key).filter { $0.value.count > 1 }
        check("No duplicate setting keys", dupes.isEmpty, dupes.keys.joined(separator: ", "))
        check("Search finds typo settings", SettingsRegistry.search("neighbor", level: .custom).contains { $0.key == K.typoNeighbor })
    }

    private static func testPresets() {
        let s = SettingsStore.shared
        let pro = BuiltInPresets.all.first { $0.name == "Pro Typist" }!
        s.apply(preset: pro)
        check("Load preset Pro Typist", s.num(K.wpm) == 125 && s.activePresetName == "Pro Typist", "wpm \(s.num(K.wpm))")
        s.set(K.countdown, 7.0)
        s.apply(preset: BuiltInPresets.all.first { $0.name == "Average Student" }!)
        check("Preset resets typing settings", s.num(K.wpm) == 55, "wpm \(s.num(K.wpm))")
        check("Preset keeps non-typing settings", s.num(K.countdown) == 7)
        s.set(K.wpm, 77.0)
        PresetStore.shared.saveCurrent(as: "E2E Test Preset")
        s.set(K.wpm, 30.0)
        if let mine = PresetStore.shared.preset(named: "E2E Test Preset") { s.apply(preset: mine) }
        check("Save + load your own preset", s.num(K.wpm) == 77, "wpm \(s.num(K.wpm))")
        s.set(K.typoMaster, 150.0)
        check("Changing a typing setting switches to Custom", s.activePresetName == Preset.customName, s.activePresetName)
        s.apply(preset: pro)
        s.set(K.countdown, 5.0)
        check("Changing a non-typing setting keeps the preset", s.activePresetName == "Pro Typist", s.activePresetName)
        s.useCustom()
        check("Pick Custom keeps current values", s.activePresetName == Preset.customName && s.num(K.wpm) == 125)
        check("Can't name a preset Custom or a built-in name", PresetStore.shared.isReserved("custom") && PresetStore.shared.isReserved("Pro Typist") && !PresetStore.shared.isReserved("My Style"))
        PresetStore.shared.rename("E2E Test Preset", to: "E2E Renamed")
        check("Rename preset", PresetStore.shared.preset(named: "E2E Renamed") != nil)
        PresetStore.shared.delete("E2E Renamed")
        check("Delete preset", PresetStore.shared.preset(named: "E2E Renamed") == nil)
    }

    private static func testExportImport() {
        let s = SettingsStore.shared
        s.set(K.wpm, 91.0)
        s.set(K.accent, "green")
        guard let data = s.exportBundle(includePresets: true) else { check("Export settings", false); return }
        check("Export settings", data.count > 10, "\(data.count) bytes")
        s.set(K.wpm, 20.0)
        s.set(K.accent, "red")
        do {
            try s.importBundle(data)
            check("Import settings", s.num(K.wpm) == 91 && s.str(K.accent) == "green", "wpm \(s.num(K.wpm)) accent \(s.str(K.accent))")
        } catch { check("Import settings", false, "\(error)") }
    }

    // MARK: Clipboard

    private static func testClipboard() {
        let cm = ClipboardManager.shared
        let s = SettingsStore.shared
        cm._testRestore([], current: "")
        s.set(K.historySize, 3.0)
        let pb = NSPasteboard.general

        pb.clearContents()
        let rich = NSAttributedString(string: "Bold rich text", attributes: [.font: NSFont.boldSystemFont(ofSize: 20)])
        pb.writeObjects([rich])
        cm.poll()
        check("Rich text → plain text", cm.currentText == "Bold rich text", "got \(cm.currentText.debugDescription)")

        pb.clearContents()
        pb.setData(Data("<p>Hello <b>HTML</b></p>".utf8), forType: .html)
        cm.poll()
        check("HTML → plain text", cm.currentText.trimmingCharacters(in: .whitespacesAndNewlines) == "Hello HTML",
              "got \(cm.currentText.debugDescription)")

        pb.clearContents()
        pb.setString("secret-password-123", forType: .string)
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        cm.poll()
        check("Concealed (password) clipboard is skipped", !cm.items.contains { $0.text == "secret-password-123" })

        pb.clearContents()
        let img = NSImage(size: NSSize(width: 4, height: 4))
        img.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 4, height: 4).fill(); img.unlockFocus()
        pb.writeObjects([img])
        let before = cm.items.count
        cm.poll()
        check("Images are ignored", cm.items.count == before)

        for t in ["one", "two", "three", "four", "five"] { cm._testAdd(t) }
        check("History size limit (3)", cm.items.count == 3 && cm.items.first?.text == "five", "\(cm.items.map(\.text))")
        if let three = cm.items.first(where: { $0.text == "three" }) { cm.togglePin(three) }
        for t in ["six", "seven", "eight"] { cm._testAdd(t) }
        check("Pinned item survives", cm.items.contains { $0.text == "three" && $0.pinned }, "\(cm.items.map(\.text))")
        cm._testAdd("six")
        check("Duplicates move to top", cm.items.first?.text == "six" && cm.items.filter { $0.text == "six" }.count == 1)
        if let seven = cm.items.first(where: { $0.text == "seven" }) {
            cm.select(seven)
            check("Pick from history replaces clipboard", pb.string(forType: .string) == "seven" && cm.currentText == "seven")
            if let sel = cm.items.first(where: { $0.text == "seven" }) { cm.update(sel, text: "seven edited") }
            check("Edit entry updates clipboard", pb.string(forType: .string) == "seven edited")
        }
    }

    private static func testHotkeys() {
        HotkeyManager.shared.registerAll()
        check("5 global hotkeys registered", HotkeyManager.shared.active.count == 5, "\(HotkeyManager.shared.active.count)")
        let combo = HotkeyCombo.defaultStart
        check("Hotkey display", combo.display == "⌃⌥⌘S", combo.display)
        check("Hotkey storage round-trip", HotkeyCombo(storage: combo.storage) == combo)
    }

    private static func testMask() {
        AppDelegate.shared?.showControlPanel()
        let app = AppDelegate.shared!
        app.setMasked(true)
        let panelHidden = !(WindowManager.shared.window(.controlPanel)?.isVisible ?? false)
        check("Mask hides windows", AppState.shared.isMasked && panelHidden)
        check("Mask hides Dock icon", NSApp.activationPolicy() == .accessory)
        app.setMasked(false)
        check("Unmask restores windows", !AppState.shared.isMasked && (WindowManager.shared.window(.controlPanel)?.isVisible ?? false))
    }

    private static func testSettingsSidebar() async {
        AppDelegate.shared?.showSettings(tab: .general)
        await sleep(1.0)
        guard let w = WindowManager.shared.window(.settings) else { check("Settings window opens", false); return }
        check("Settings window opens", w.isVisible)
        guard AXIsProcessTrusted() else { log("SKIP  sidebar click test (needs Accessibility)"); return }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        await sleep(0.5)
        // Click each of the first few sidebar rows and confirm the tab changes.
        let tabs = SettingTab.allCases.filter { $0.minLevel <= SettingsStore.shared.uiLevel }
        var ok = true
        for tab in tabs.reversed() where tab != .presets {
            guard let p = rowPoint("tab.\(tab.rawValue)", in: w) else { ok = false; log("      couldn't find sidebar row \(tab.title)"); continue }
            click(at: p)
            await sleep(0.35)
            if SettingsNavigation.shared.selectedTab != tab { ok = false; log("      clicked \(tab.title) got \(SettingsNavigation.shared.selectedTab)") }
        }
        check("Sidebar clicks switch tabs", ok)

        // Presets page: click rows (not the Load button) and confirm the selection changes.
        SettingsNavigation.shared.selectedTab = .presets
        await sleep(0.8)
        let store = SettingsStore.shared
        if let casual = rowPoint("preset.Casual", in: w, xFraction: 0.4) {
            click(at: casual)
            await sleep(0.5)
            check("Click a preset row selects it", store.activePresetName == "Casual" && store.num(K.wpm) == 42,
                  "\(store.activePresetName), wpm \(store.num(K.wpm))")
        } else { check("Click a preset row selects it", false, "couldn't find the Casual row") }
        if let custom = rowPoint("preset.\(Preset.customName)", in: w, xFraction: 0.4) {
            click(at: custom)
            await sleep(0.5)
            check("Click the Custom row selects Custom", store.activePresetName == Preset.customName, store.activePresetName)
        } else { check("Click the Custom row selects Custom", false, "couldn't find the Custom row") }
        SettingsNavigation.shared.selectedTab = .general
        WindowManager.shared.close(.settings)
        WindowManager.shared.close(.controlPanel)
    }

    // MARK: Real typing

    private struct Case {
        let name: String
        let text: String
        var overrides: [String: SettingValue] = [:]
        var verify = false
        var pauseTest = false
        var inPad = true
    }

    // MARK: Test pad: a plain text box with every macOS correction turned off.

    private static var padWindow: NSWindow?
    private static var padView: NSTextView?

    private static func openPad() async -> NSTextView {
        if padWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 700, height: 420),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "Handwritten Test Pad"
            w.isReleasedWhenClosed = false
            let scroll = NSTextView.scrollableTextView()
            let tv = scroll.documentView as! NSTextView
            tv.isRichText = false
            tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            tv.isAutomaticSpellingCorrectionEnabled = false
            tv.isAutomaticQuoteSubstitutionEnabled = false
            tv.isAutomaticDashSubstitutionEnabled = false
            tv.isAutomaticTextReplacementEnabled = false
            tv.isAutomaticTextCompletionEnabled = false
            tv.isAutomaticDataDetectionEnabled = false
            tv.isAutomaticLinkDetectionEnabled = false
            tv.isContinuousSpellCheckingEnabled = false
            tv.isGrammarCheckingEnabled = false
            tv.smartInsertDeleteEnabled = false
            if #available(macOS 14.0, *) { tv.inlinePredictionType = .no }
            w.contentView = scroll
            padWindow = w
            padView = tv
        }
        padView!.string = ""
        NSApp.activate(ignoringOtherApps: true)
        padWindow!.makeKeyAndOrderFront(nil)
        padWindow!.makeFirstResponder(padView)
        await sleep(0.6)
        return padView!
    }

    private static func baseOverrides() -> [String: SettingValue] {
        [K.wpm: .number(220), K.useSeed: .bool(true), K.seed: .number(7), K.thinkEnabled: .bool(false),
         K.pausePeriod: .number(60), K.pauseNewline: .number(60), K.pauseParagraph: .number(80), K.pauseComma: .number(30),
         K.rereadChance: .number(0), K.warmupSeconds: .number(0), K.noticeMin: .number(40), K.noticeMax: .number(90),
         K.longWordPause: .number(0), K.rareWordChance: .number(0), K.hesitationChance: .number(0),
         K.proofreadArrowSpeed: .number(25), K.newlineMode: .text("return")]
    }

    private static func testTyping() async {
        let sentence = "The quick brown fox jumps over the lazy dog, and then it naps because it was definitely tired. We're going to the restaurant tomorrow."
        let heavy: [String: SettingValue] = [K.typoMaster: .number(350), K.typoMinGap: .number(2), K.fixLateWeight: .number(40),
                                              K.overDeleteChance: .number(40), K.wordDeleteChance: .number(40), K.typoWhileFixing: .number(30),
                                              K.leaveUnfixed: .number(15), K.proofreadAtEnd: .bool(true), K.typoMisspell: .number(80)]
        let cases: [Case] = [
            Case(name: "Plain text, no typos", text: sentence, overrides: [K.typosEnabled: .bool(false)]),
            Case(name: "Heavy typos + every fix style + proofread", text: sentence, overrides: heavy),
            Case(name: "Mostly late arrow-key fixes", text: sentence,
                 overrides: heavy.merging([K.fixLateWeight: .number(90), K.leaveUnfixed: .number(0)]) { $1 }),
            Case(name: "Safe typo mode", text: sentence, overrides: heavy.merging([K.safeTypoMode: .bool(true)]) { $1 }),
            Case(name: "Emoji, accents, symbols, other languages",
                 text: "Emoji 😀👍🏽🇺🇸 café naïve jalapeño — ≤ ≥ → ∑ ∫ © ™ ¿Qué tal? 日本語 Привет ünïcödé",
                 overrides: [K.typoMaster: .number(200)]),
            Case(name: "All keyboard symbols", text: "!@#$%^&*()_+-=[]{}\\|;:'\",.<>/?`~ 1234567890",
                 overrides: [K.typosEnabled: .bool(false)]),
            Case(name: "Multiple lines (Return)", text: "Line one is here.\nLine two has more words.\n\nNew paragraph after a blank line.",
                 overrides: [K.typoMaster: .number(250)]),
            Case(name: "Multiple lines (Shift+Return)", text: "First line\nSecond line\nThird line",
                 overrides: [K.newlineMode: .text("shiftReturn"), K.typosEnabled: .bool(false)]),
            Case(name: "Tabs as Tab key", text: "a\tb\tc", overrides: [K.typosEnabled: .bool(false)]),
            Case(name: "Tabs as spaces", text: "a\tb", overrides: [K.typosEnabled: .bool(false), K.tabMode: .text("spaces"), K.tabSpaces: .number(4)]),
            Case(name: "Unfixed typos, no proofread → end check fixes them", text: sentence,
                 overrides: [K.typoMaster: .number(300), K.typoMinGap: .number(3), K.leaveUnfixed: .number(100), K.proofreadAtEnd: .bool(false)],
                 verify: true),
            Case(name: "Pause and resume mid-run", text: sentence + " " + sentence,
                 overrides: heavy.merging([K.wpm: .number(120)]) { $1 }, pauseTest: true),
            Case(name: "Timer mode (8 seconds)", text: "Short text typed in timer mode to check the timing is right.",
                 overrides: [K.speedMode: .text("timer"), K.timerMinutes: .number(8.0 / 60.0), K.typosEnabled: .bool(false)]),
        ]
        // Real world: TextEdit with your Mac's normal autocorrect, default protection + end check.
        let real: [String: SettingValue] = [K.typoMaster: .number(250), K.typoMinGap: .number(3), K.autocorrectProtection: .text("auto"),
                                             K.verifyEnabled: .bool(true)]
        let realCases: [Case] = [
            Case(name: "Heavy typos with Mac autocorrect on", text: sentence, overrides: real, verify: true, inPad: false),
            Case(name: "Emoji and accents with Mac autocorrect on", text: "Emoji 😀👍🏽 café naïve jalapeño — ¿Qué tal? 日本語 Привет",
                 overrides: real, verify: true, inPad: false),
            Case(name: "Paragraphs with Mac autocorrect on", text: "Line one is here.\nLine two has more words.\n\nNew paragraph after a blank line.",
                 overrides: real, verify: true, inPad: false),
            Case(name: "Double spaces with Mac period substitution on", text: "Two  spaces here.  And   three there. The end",
                 overrides: real.merging([K.typosEnabled: .bool(false)]) { $1 }, inPad: false),
            Case(name: "Pause and resume with Mac autocorrect on", text: sentence + " " + sentence,
                 overrides: real.merging([K.wpm: .number(150)]) { $1 }, verify: true, pauseTest: true, inPad: false),
        ]
        // Engine correctness in a clean text box (no Mac corrections).
        let padOverrides: [String: SettingValue] = [K.autocorrectProtection: .text("off")]
        for (n, c) in cases.enumerated() {
            var c2 = c
            c2 = Case(name: c.name, text: c.text, overrides: padOverrides.merging(c.overrides) { $1 },
                      verify: c.verify, pauseTest: c.pauseTest, inPad: true)
            await runCase(c2, index: n)
        }
        padWindow?.orderOut(nil)
        for (n, c) in realCases.enumerated() {
            await runCase(c, index: 100 + n)
        }
    }

    private static func runCase(_ c: Case, index: Int) async {
        let file = dir.appendingPathComponent("case\(index).txt")
        var pad: NSTextView?
        if c.inPad {
            pad = await openPad()
        } else {
            try? "".write(to: file, atomically: true, encoding: .utf8)
            guard await openInTextEdit(file) else { check(c.name, false, "TextEdit didn't come to the front"); return }
        }
        let label = (c.inPad ? "[Test pad] " : "[TextEdit] ") + c.name

        var vals = SettingsStore.shared.snapshot.values
        for (k, v) in baseOverrides() { vals[k] = v }
        for (k, v) in c.overrides { vals[k] = v }
        let snap = SettingsSnapshot(values: vals)
        let prepared = TextPreparer.prepare(c.text, snap)
        let plan = Planner.makePlan(text: prepared, settings: snap, words: WordData.shared.snapshot())
        let engine = TypingEngine()
        engine.configure(snap)
        let t0 = Date()
        engine.start(plan)

        if c.pauseTest {
            await sleep(min(3, plan.totalDuration * 0.4))
            engine.requestPause()
            await sleep(0.3)
            let len1 = Verifier.readViaAccessibility()?.text.count ?? -1
            await sleep(1.5)
            let len2 = Verifier.readViaAccessibility()?.text.count ?? -2
            check("  …no typing while paused", len1 == len2 && len1 >= 0, "length \(len1) → \(len2)")
            engine.resume()
        }
        while engine.isRunning { await sleep(0.1) }
        let elapsed = Date().timeIntervalSince(t0)

        if c.verify {
            let msg = await Task.detached { Verifier.verifyAndFix(expected: prepared, settings: snap, engine: engine) }.value
            log("      end check: \(msg)")
        }
        await sleep(0.3)
        let saved: String
        if let pad {
            saved = pad.string
        } else {
            engine.keySender.tap(UInt16(kVK_ANSI_S), flags: .maskCommand, hold: 0.03)
            await sleep(1.0)
            saved = (try? String(contentsOf: file, encoding: .utf8)) ?? "<unreadable>"
        }
        let norm = normalize(saved)
        let expected = normalize(prepared)
        let match = norm == expected
        var detail = String(format: "%d chars, %d typos, %.1fs (planned %.1fs)", prepared.count, plan.typoCount, elapsed, plan.totalDuration)
        if !match { detail += "\n      EXPECTED: \(expected.debugDescription)\n      GOT:      \(norm.debugDescription)" }
        check(label, match, detail)
        if c.name.hasPrefix("Timer") {
            check("  …timer mode took about 8s", abs(elapsed - 8) < 1.5, String(format: "%.2fs", elapsed))
        }
        if !c.pauseTest && !c.verify && plan.totalDuration > 2 {
            let drift = abs(elapsed - plan.totalDuration) / plan.totalDuration
            check("  …ETA accurate (within 15%)", drift < 0.15, String(format: "%.0f%% off", drift * 100))
        }
        if !c.inPad {
            engine.keySender.tap(UInt16(kVK_ANSI_W), flags: .maskCommand, hold: 0.03)
            await sleep(0.6)
        }
    }

    // MARK: Controller-level: Escape + auto-pause

    private static func testControllerEscapeAndAutoPause() async {
        let s = SettingsStore.shared
        for (k, v) in baseOverrides() { s.set(k, v, manual: false) }
        s.set(K.countdown, 0.0)
        s.set(K.showHUD, true)
        s.set(K.verifyEnabled, false)
        let long = String(repeating: "Typing a long text so there is time to interrupt it. ", count: 10)

        // Escape
        var file = dir.appendingPathComponent("escape.txt")
        try? "".write(to: file, atomically: true, encoding: .utf8)
        if await openInTextEdit(file) {
            TypingController.shared.start(text: long)
            await sleep(1.5)
            check("Start via controller → typing", AppState.shared.runState == .typing, "\(AppState.shared.runState)")
            check("Progress HUD shows while typing", WindowManager.shared.isVisible(.hud))
            postUserKey(UInt16(kVK_Escape))
            await sleep(0.5)
            check("Escape stops typing", AppState.shared.runState == .idle, "\(AppState.shared.runState)")
            TypingController.shared.stop()
            closeFront()
            await sleep(0.6)
        }

        // Auto-pause on a key press, then resume with countdown and finish correctly.
        file = dir.appendingPathComponent("autopause.txt")
        try? "".write(to: file, atomically: true, encoding: .utf8)
        if await openInTextEdit(file) {
            s.set(K.resumeCountdown, 1.0)
            let text = "Auto pause test sentence that should still come out perfectly at the end."
            TypingController.shared.start(text: text)
            await sleep(1.2)
            postUserKey(UInt16(kVK_F15))
            await sleep(0.4)
            check("Your key press auto-pauses", AppState.shared.runState == .paused, "\(AppState.shared.runState)")
            TypingController.shared.resume()
            await sleep(0.3)
            check("Resume counts down first", AppState.shared.runState.isCountdown, "\(AppState.shared.runState)")
            while AppState.shared.runState != .idle { await sleep(0.2) }
            TypingController.shared.engine.keySender.tap(UInt16(kVK_ANSI_S), flags: .maskCommand, hold: 0.03)
            await sleep(1.0)
            let saved = normalize((try? String(contentsOf: file, encoding: .utf8)) ?? "")
            check("Text is perfect after auto-pause + resume", saved == normalize(text), saved.debugDescription)
            closeFront()
            await sleep(0.6)
        }

        // Auto-pause on app switch.
        file = dir.appendingPathComponent("appswitch.txt")
        try? "".write(to: file, atomically: true, encoding: .utf8)
        if await openInTextEdit(file) {
            TypingController.shared.start(text: long)
            await sleep(1.2)
            let calc = URL(fileURLWithPath: "/System/Applications/Calculator.app")
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: calc, configuration: cfg)
            await sleep(1.5)
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
            if front == "com.apple.calculator" {
                check("Switching apps auto-pauses", AppState.shared.runState == .paused, "\(AppState.shared.runState)")
            } else {
                // macOS didn't let a background app bring Calculator forward; deliver the switch event directly.
                log("      (Calculator didn't come to the front — frontmost is \(front); simulating the app-switch event)")
                if let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.calculator").first?.processIdentifier {
                    InputMonitor.shared.onAppSwitch?(pid)
                }
                await sleep(0.3)
                check("Switching apps auto-pauses (simulated switch)", AppState.shared.runState == .paused, "\(AppState.shared.runState)")
            }
            TypingController.shared.stop()
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.calculator").first?.terminate()
            await sleep(0.5)
            _ = await openInTextEdit(file)
            closeFront(save: false)
            await sleep(0.6)
        }
    }

    // MARK: Helpers

    private static func openInTextEdit(_ file: URL) async -> Bool {
        let te = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        _ = try? await NSWorkspace.shared.open([file], withApplicationAt: te, configuration: cfg)
        for _ in 0..<30 {
            await sleep(0.2)
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.TextEdit" {
                await sleep(0.8)
                return true
            }
        }
        return false
    }

    private static func closeFront(save: Bool = true) {
        let ks = KeySender()
        if save { ks.tap(UInt16(kVK_ANSI_S), flags: .maskCommand, hold: 0.03) }
        Thread.sleep(forTimeInterval: 0.4)
        ks.tap(UInt16(kVK_ANSI_W), flags: .maskCommand, hold: 0.03)
        Thread.sleep(forTimeInterval: 0.4)
        if !save { ks.tap(UInt16(kVK_ANSI_D), flags: .maskCommand, hold: 0.03) } // "Don't Save"
    }

    private static func normalize(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\u{2028}", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        t = t.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "‘", with: "'").replacingOccurrences(of: "’", with: "'")
        while t.hasSuffix("\n") && !s.isEmpty { t.removeLast() }
        return t
    }

    /// A key press that looks like it came from the user (no Handwritten marker).
    private static func postUserKey(_ code: UInt16) {
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
    }

    private static func click(at cocoa: NSPoint) {
        let h = NSScreen.screens.first?.frame.height ?? 0
        let p = CGPoint(x: cocoa.x, y: h - cocoa.y)
        let src = CGEventSource(stateID: .privateState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
            e?.setIntegerValueField(.eventSourceUserData, value: KeySender.marker)
            e?.post(tap: .cghidEventTap)
        }
    }

    /// Screen point (Cocoa coords) inside a row the view recorded.
    private static func rowPoint(_ id: String, in w: NSWindow, xFraction: CGFloat = 0.5) -> NSPoint? {
        guard let r = SettingsNavigation.shared.rowFrames[id], r.width > 0 else { return nil }
        let contentTop = w.contentLayoutRect.maxY == 0 ? w.frame.height : w.frame.height
        _ = contentTop
        return NSPoint(x: w.frame.minX + r.minX + r.width * xFraction, y: w.frame.maxY - r.midY)
    }

    /// Finds a text element in our own window via Accessibility and returns its center (Cocoa coords).
    private static func findText(_ text: String, in window: NSWindow) -> NSPoint? {
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var found: CGRect?
        func visit(_ el: AXUIElement, depth: Int) {
            guard found == nil, depth < 40 else { return }
            var v: CFTypeRef?
            for attr in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
                if AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let s = v as? String, s == text {
                    var pos: CFTypeRef?, size: CFTypeRef?
                    AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pos)
                    AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &size)
                    var p = CGPoint.zero, sz = CGSize.zero
                    if let pos { AXValueGetValue(pos as! AXValue, .cgPoint, &p) }
                    if let size { AXValueGetValue(size as! AXValue, .cgSize, &sz) }
                    if sz.width > 0 { found = CGRect(origin: p, size: sz); return }
                }
            }
            var kids: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kids) == .success, let arr = kids as? [AXUIElement] {
                for k in arr { visit(k, depth: depth + 1) }
            }
        }
        visit(app, depth: 0)
        guard let r = found else { return nil }
        let h = NSScreen.screens.first?.frame.height ?? 0
        return NSPoint(x: r.midX, y: h - r.midY) // AX is top-left origin
    }

    private static func savePasteboard() -> [NSPasteboardItem] {
        NSPasteboard.general.pasteboardItems?.map { item in
            let c = NSPasteboardItem()
            for t in item.types { if let d = item.data(forType: t) { c.setData(d, forType: t) } }
            return c
        } ?? []
    }

    private static func restorePasteboard(_ items: [NSPasteboardItem]) {
        NSPasteboard.general.clearContents()
        if !items.isEmpty { NSPasteboard.general.writeObjects(items) }
        ClipboardManager.shared.ignoreCurrentChangeCount()
    }
}
