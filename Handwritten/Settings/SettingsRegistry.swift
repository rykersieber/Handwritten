import Foundation

/// Setting keys used throughout the app.
enum K {
    // General
    static let countdown = "gen.countdown"
    static let resumeCountdown = "gen.resumeCountdown"
    static let autoPauseClick = "gen.autoPauseClick"
    static let autoPauseAppSwitch = "gen.autoPauseAppSwitch"
    static let autoPauseKeypress = "gen.autoPauseKeypress"
    static let ignoreClicksOnOwnWindows = "gen.ignoreOwnClicks"
    static let escapeStops = "gen.escapeStops"
    static let warnOnResume = "gen.warnOnResume"
    static let finishFixBeforePause = "gen.finishFixBeforePause"
    static let showPercent = "gen.showPercent"
    static let showCountdownInMenu = "gen.showCountdownInMenu"
    static let showHUD = "gen.showHUD"
    static let hudShowsETA = "gen.hudShowsETA"
    static let launchAtLogin = "gen.launchAtLogin"
    static let showDockIcon = "gen.showDockIcon"
    static let openPanelOnLaunch = "gen.openPanelOnLaunch"
    static let typingInto = "gen.typingInto"
    static let restoreClipboardAfter = "gen.restoreClipboard"

    // Speed
    static let speedMode = "speed.mode"
    static let wpm = "speed.wpm"
    static let timerMinutes = "speed.timerMinutes"
    static let timerMinWPM = "speed.timerMinWPM"
    static let timerMaxWPM = "speed.timerMaxWPM"
    static let timerScaleMode = "speed.timerScaleMode"
    static let humanness = "speed.humanness"
    static let variation = "speed.variation"
    static let distribution = "speed.distribution"
    static let minKeyDelay = "speed.minKeyDelay"
    static let maxKeyDelay = "speed.maxKeyDelay"
    static let holdMin = "speed.holdMin"
    static let holdMax = "speed.holdMax"
    static let shiftPenalty = "speed.shiftPenalty"
    static let numberRowPenalty = "speed.numberRowPenalty"
    static let symbolPenalty = "speed.symbolPenalty"
    static let unicodePenalty = "speed.unicodePenalty"
    static let sameFingerPenalty = "speed.sameFingerPenalty"
    static let sameKeyRepeat = "speed.sameKeyRepeat"
    static let handAlternation = "speed.handAlternation"
    static let rowJumpPenalty = "speed.rowJumpPenalty"
    static let capitalAfterSpace = "speed.capitalAfterSpace"
    static let bigramBurst = "speed.bigramBurst"
    static let bigramBurstChance = "speed.bigramBurstChance"
    static let wordBurst = "speed.wordBurst"
    static let wordBurstChance = "speed.wordBurstChance"
    static let randomBurstChance = "speed.randomBurstChance"
    static let randomBurstMult = "speed.randomBurstMult"
    static let randomBurstLength = "speed.randomBurstLength"
    static let warmupSeconds = "speed.warmupSeconds"
    static let warmupMult = "speed.warmupMult"
    static let fatiguePerMinute = "speed.fatiguePerMinute"
    static let fatigueMax = "speed.fatigueMax"
    static let driftAmount = "speed.driftAmount"
    static let driftPeriod = "speed.driftPeriod"
    static func finger(_ f: Int) -> String { "speed.finger.\(f)" }
    static func row(_ r: Int) -> String { "speed.row.\(r)" }

    // Rhythm
    static let pauseSpace = "rhythm.pauseSpace"
    static let pauseComma = "rhythm.pauseComma"
    static let pausePeriod = "rhythm.pausePeriod"
    static let pauseQuestion = "rhythm.pauseQuestion"
    static let pauseColon = "rhythm.pauseColon"
    static let pauseDash = "rhythm.pauseDash"
    static let pauseQuote = "rhythm.pauseQuote"
    static let pauseBracket = "rhythm.pauseBracket"
    static let pauseNewline = "rhythm.pauseNewline"
    static let pauseParagraph = "rhythm.pauseParagraph"
    static let pauseJitter = "rhythm.pauseJitter"
    static let wordStartMult = "rhythm.wordStartMult"
    static let longWordLength = "rhythm.longWordLength"
    static let longWordPause = "rhythm.longWordPause"
    static let rareWordPause = "rhythm.rareWordPause"
    static let rareWordChance = "rhythm.rareWordChance"
    static let numberSlowdown = "rhythm.numberSlowdown"
    static let capsWordSlowdown = "rhythm.capsWordSlowdown"
    static let thinkEnabled = "rhythm.thinkEnabled"
    static let thinkChanceWord = "rhythm.thinkChanceWord"
    static let thinkChanceSentence = "rhythm.thinkChanceSentence"
    static let thinkChanceParagraph = "rhythm.thinkChanceParagraph"
    static let thinkMin = "rhythm.thinkMin"
    static let thinkMax = "rhythm.thinkMax"
    static let hesitationChance = "rhythm.hesitationChance"
    static let hesitationMin = "rhythm.hesitationMin"
    static let hesitationMax = "rhythm.hesitationMax"
    static let rereadChance = "rhythm.rereadChance"
    static let rereadMin = "rhythm.rereadMin"
    static let rereadMax = "rhythm.rereadMax"
    static let breakEnabled = "rhythm.breakEnabled"
    static let breakChancePerMinute = "rhythm.breakChancePerMinute"
    static let breakMin = "rhythm.breakMin"
    static let breakMax = "rhythm.breakMax"
    static let breakMinGap = "rhythm.breakMinGap"

    // Typos
    static let typosEnabled = "typo.enabled"
    static let typoMaster = "typo.master"
    static let typoNeighbor = "typo.neighbor"
    static let typoTranspose = "typo.transpose"
    static let typoDouble = "typo.double"
    static let typoSkip = "typo.skip"
    static let typoShift = "typo.shift"
    static let typoShiftHold = "typo.shiftHold"
    static let typoFatFinger = "typo.fatFinger"
    static let typoMirror = "typo.mirror"
    static let typoSpace = "typo.space"
    static let typoPunct = "typo.punct"
    static let typoMisspell = "typo.misspell"
    static let typoWrongWord = "typo.wrongWord"
    static let typoDiagonalWeight = "typo.diagonalWeight"
    static let typoWordStartMult = "typo.wordStartMult"
    static let typoWordEndMult = "typo.wordEndMult"
    static let typoLongWordMult = "typo.longWordMult"
    static let typoBurstMult = "typo.burstMult"
    static let typoFatigueMult = "typo.fatigueMult"
    static let typoMaxPerWord = "typo.maxPerWord"
    static let typoMinGap = "typo.minGap"
    static let typoSkipURLs = "typo.skipURLs"
    static let typoSkipEmails = "typo.skipEmails"
    static let typoSkipNumbers = "typo.skipNumbers"
    static let typoSkipCode = "typo.skipCode"
    static let typoSkipAllCaps = "typo.skipAllCaps"
    static let typoSkipCapitalized = "typo.skipCapitalized"
    static let typoSkipShortWords = "typo.skipShortWords"
    static let typoSkipFirstWords = "typo.skipFirstWords"
    static let typoSkipNonLatin = "typo.skipNonLatin"
    static let safeTypoMode = "typo.safeMode"
    static let autocorrectProtection = "typo.autocorrectProtection"
    static let autocorrectReminder = "typo.autocorrectReminder"

    // Corrections
    static let fixImmediateWeight = "fix.immediateWeight"
    static let fixDelayedWeight = "fix.delayedWeight"
    static let fixDelayedMin = "fix.delayedMin"
    static let fixDelayedMax = "fix.delayedMax"
    static let fixEndOfWordWeight = "fix.endOfWordWeight"
    static let fixLateWeight = "fix.lateWeight"
    static let fixLateMin = "fix.lateMin"
    static let fixLateMax = "fix.lateMax"
    static let leaveUnfixed = "fix.leaveUnfixed"
    static let proofreadAtEnd = "fix.proofreadAtEnd"
    static let noticeMin = "fix.noticeMin"
    static let noticeMax = "fix.noticeMax"
    static let backspaceSpeed = "fix.backspaceSpeed"
    static let backspaceVariation = "fix.backspaceVariation"
    static let wordDeleteChance = "fix.wordDeleteChance"
    static let wordDeleteMinChars = "fix.wordDeleteMinChars"
    static let overDeleteChance = "fix.overDeleteChance"
    static let overDeleteMax = "fix.overDeleteMax"
    static let typoWhileFixing = "fix.typoWhileFixing"
    static let arrowSpeed = "fix.arrowSpeed"
    static let pauseAfterFix = "fix.pauseAfterFix"
    static let retypeSlowdown = "fix.retypeSlowdown"
    static let verifyEnabled = "fix.verifyEnabled"
    static let verifyMethod = "fix.verifyMethod"
    static let verifyDelay = "fix.verifyDelay"
    static let verifyMaxFixes = "fix.verifyMaxFixes"
    static let verifyMinSimilarity = "fix.verifyMinSimilarity"
    static let verifyIgnoreSmartQuotes = "fix.verifyIgnoreSmartQuotes"
    static let verifySpeed = "fix.verifySpeed"
    static let proofreadArrowSpeed = "fix.proofreadArrowSpeed"

    // Text handling
    static let newlineMode = "text.newlineMode"
    static let tabMode = "text.tabMode"
    static let tabSpaces = "text.tabSpaces"
    static let codeMode = "text.codeMode"
    static let codeIndentMode = "text.codeIndentMode"
    static let codeAutoCloseMode = "text.codeAutoCloseMode"
    static let keyMethod = "text.keyMethod"
    static let smartQuotesToStraight = "text.smartQuotesToStraight"
    static let doubleSpaceGuard = "text.doubleSpaceGuard"
    static let trimTrailingWhitespace = "text.trimTrailing"
    static let trimEnds = "text.trimEnds"
    static let collapseBlankLines = "text.collapseBlankLines"
    static let nbspToSpace = "text.nbspToSpace"
    static let stripZeroWidth = "text.stripZeroWidth"
    static let maxChars = "text.maxChars"

    // Clipboard
    static let historySize = "clip.historySize"
    static let clearOnQuit = "clip.clearOnQuit"
    static let skipPasswordManagers = "clip.skipPasswordManagers"
    static let skipConcealed = "clip.skipConcealed"
    static let pollInterval = "clip.pollInterval"
    static let previewLength = "clip.previewLength"
    static let minLength = "clip.minLength"
    static let ignoreDuplicates = "clip.ignoreDuplicates"
    static let maxItemLength = "clip.maxItemLength"
    static let historyInMenu = "clip.historyInMenu"
    static let pinsEnabled = "clip.pinsEnabled"
    static let menuPreviewLength = "clip.menuPreviewLength"

    // Hotkeys
    static let hkStart = "hotkey.start"
    static let hkPause = "hotkey.pause"
    static let hkStop = "hotkey.stop"
    static let hkMask = "hotkey.mask"
    static let hkPanel = "hotkey.panel"
    static let hkPauseEnabled = "hotkey.pauseEnabled"
    static let hkEnabled = "hotkey.enabled"

    // Mask
    static let maskDummyIcon = "mask.dummyIcon"
    static let maskDummyStyle = "mask.dummyStyle"
    static let maskRequireOption = "mask.requireOption"
    static let maskStopsTyping = "mask.stopsTyping"
    static let maskOnLaunch = "mask.onLaunch"

    // Appearance
    static let theme = "app.theme"
    static let accent = "app.accent"
    static let customAccent = "app.customAccent"
    static let hudOpacity = "app.hudOpacity"
    static let hudScale = "app.hudScale"
    static let menuIcon = "app.menuIcon"
    static let colorIconWhenTyping = "app.colorIcon"

    // Developer
    static let useSeed = "dev.useSeed"
    static let seed = "dev.seed"
    static let dryRun = "dev.dryRun"
    static let logPlan = "dev.logPlan"
    static let timingCompensation = "dev.timingCompensation"
}

enum SettingsRegistry {
    static let all: [SettingDef] = build()
    private static let index: [String: SettingDef] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })
    static func def(_ key: String) -> SettingDef? { index[key] }

    static func defs(tab: SettingTab, level: SettingLevel) -> [SettingDef] {
        all.filter { $0.tab == tab && $0.level <= level }
    }

    static func search(_ q: String, level: SettingLevel) -> [SettingDef] {
        let terms = q.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        return all.filter { d in terms.allSatisfy { d.searchText.contains($0) } }
    }

    static let fingerNames = ["Left pinky", "Left ring", "Left middle", "Left index",
                              "Right index", "Right middle", "Right ring", "Right pinky", "Thumbs"]
    static let rowNames = ["Number row", "Top row (QWERTY)", "Home row (ASDF)", "Bottom row (ZXCV)", "Space bar"]

    // MARK: Builders

    private static func num(_ key: String, _ title: String, _ help: String,
                            _ tab: SettingTab, _ section: String, _ level: SettingLevel,
                            _ def: Double, _ min: Double, _ max: Double, _ step: Double, _ unit: String = "",
                            human: (Double, Double)? = nil, dep: String? = nil) -> SettingDef {
        SettingDef(key: key, title: title, help: help, tab: tab, section: section, level: level,
                   kind: .number(min: min, max: max, step: step, unit: unit),
                   defaultValue: .number(def), human: human, dependsOn: dep)
    }

    private static func tog(_ key: String, _ title: String, _ help: String,
                            _ tab: SettingTab, _ section: String, _ level: SettingLevel,
                            _ def: Bool, dep: String? = nil) -> SettingDef {
        SettingDef(key: key, title: title, help: help, tab: tab, section: section, level: level,
                   kind: .toggle, defaultValue: .bool(def), human: nil, dependsOn: dep)
    }

    private static func pick(_ key: String, _ title: String, _ help: String,
                             _ tab: SettingTab, _ section: String, _ level: SettingLevel,
                             _ def: String, _ options: [(String, String)], dep: String? = nil) -> SettingDef {
        SettingDef(key: key, title: title, help: help, tab: tab, section: section, level: level,
                   kind: .choice(options.map { ChoiceOption(value: $0.0, label: $0.1) }),
                   defaultValue: .text(def), human: nil, dependsOn: dep)
    }

    private static func txt(_ key: String, _ title: String, _ help: String,
                            _ tab: SettingTab, _ section: String, _ level: SettingLevel,
                            _ def: String, placeholder: String = "", kind: SettingKind? = nil, dep: String? = nil) -> SettingDef {
        SettingDef(key: key, title: title, help: help, tab: tab, section: section, level: level,
                   kind: kind ?? .text(placeholder: placeholder), defaultValue: .text(def), human: nil, dependsOn: dep)
    }

    // swiftlint:disable function_body_length
    private static func build() -> [SettingDef] {
        var d: [SettingDef] = []

        // MARK: General
        let g = SettingTab.general
        d += [
            num(K.countdown, "Countdown before typing", "Seconds to wait after pressing Start so you can click into the text box. Clicks are ignored during the countdown.", g, "Starting", .simple, 3, 0, 30, 1, "s"),
            num(K.resumeCountdown, "Countdown before resuming", "Seconds to wait after Resume before typing continues.", g, "Starting", .advanced, 3, 0, 30, 1, "s"),
            pick(K.typingInto, "Typing into", "Quick profile that sets newline, tab and code editor behavior for the kind of app you're typing into.", g, "Starting", .simple, "general",
                 [("general", "General"), ("browser", "Browser"), ("word", "Word / Pages"), ("code", "Code Editor")]),
            tog(K.autoPauseClick, "Auto-pause when you click", "Pauses typing if you click the mouse anywhere while it's typing. Moving the mouse never pauses.", g, "Auto-pause", .simple, true),
            tog(K.autoPauseAppSwitch, "Auto-pause when the app or window changes", "Pauses if a different app becomes active while typing.", g, "Auto-pause", .simple, true),
            tog(K.autoPauseKeypress, "Auto-pause when you press a key", "Pauses if you press any key yourself while it's typing (except the hotkeys).", g, "Auto-pause", .advanced, true),
            tog(K.ignoreClicksOnOwnWindows, "Ignore clicks on Handwritten's own windows", "Clicking the progress bar or control panel won't trigger auto-pause.", g, "Auto-pause", .advanced, true),
            tog(K.escapeStops, "Escape always stops", "Pressing Escape stops typing immediately.", g, "Stopping", .simple, true),
            tog(K.warnOnResume, "Warn before resuming", "Shows a reminder to put the cursor back before typing resumes.", g, "Pause & resume", .advanced, false),
            tog(K.finishFixBeforePause, "Finish fixing a typo before pausing", "If off, pause happens immediately and the fix finishes when you resume.", g, "Pause & resume", .advanced, false),
            tog(K.showPercent, "Show percentage in menu bar", "Shows progress next to the menu bar icon while typing.", g, "Display", .simple, true),
            tog(K.showCountdownInMenu, "Show countdown in menu bar", "Shows the countdown number in the menu bar.", g, "Display", .advanced, true),
            tog(K.showHUD, "Show floating progress bar", "A small movable progress window while typing.", g, "Display", .simple, true),
            tog(K.hudShowsETA, "Progress bar shows time remaining", "Show the countdown of time left in the progress bar.", g, "Display", .advanced, true),
            tog(K.openPanelOnLaunch, "Open control panel on launch", "Shows the control panel when Handwritten starts.", g, "Launch", .advanced, true),
            tog(K.launchAtLogin, "Launch at login", "Start Handwritten automatically when you log in.", g, "Launch", .simple, false),
            tog(K.showDockIcon, "Show Dock icon", "Show Handwritten in the Dock and ⌘-Tab (it always lives in the menu bar).", g, "Launch", .advanced, false),
            tog(K.restoreClipboardAfter, "Restore clipboard after verification", "Puts your clipboard back after the end-of-run check copies the text box.", g, "Clipboard safety", .custom, true),
        ]

        // MARK: Speed
        let s = SettingTab.speed
        d += [
            num(K.humanness, "Humanness", "Master slider. 0% types like a robot (steady, no typos or pauses). 100% is a sloppy, distracted human. Moves many settings at once; settings you change by hand are left alone.", s, "Master", .simple, 50, 0, 100, 1, "%"),
            pick(K.speedMode, "Speed mode", "WPM: set the speed and see how long it will take. Timer: set how long it should take and the speed adjusts.", s, "Mode", .simple, "wpm",
                 [("wpm", "Words per minute"), ("timer", "Timer (total time)")]),
            num(K.wpm, "Typing speed", "Average words per minute (a word = 5 characters).", s, "Mode", .simple, 55, 5, 250, 1, "WPM"),
            num(K.timerMinutes, "Target time", "In timer mode, roughly how long the whole run should take.", s, "Mode", .simple, 10, 0.1, 600, 0.5, "min"),
            num(K.timerMinWPM, "Timer: slowest allowed speed", "Timer mode won't type slower than this; remaining time goes into pauses.", s, "Timer mode", .advanced, 15, 1, 200, 1, "WPM"),
            num(K.timerMaxWPM, "Timer: fastest allowed speed", "Timer mode won't type faster than this.", s, "Timer mode", .advanced, 140, 5, 300, 1, "WPM"),
            pick(K.timerScaleMode, "Timer: how to fill time", "Balanced scales speed within the limits, then pauses. Pauses-first keeps your speed and stretches pauses. Uniform scales everything equally.", s, "Timer mode", .advanced, "balanced",
                 [("balanced", "Balanced"), ("pauses", "Pauses first"), ("uniform", "Uniform")]),
            num(K.variation, "Speed variation", "How much each keystroke's timing randomly varies.", s, "Variation", .simple, 35, 0, 150, 1, "%", human: (0, 70)),
            pick(K.distribution, "Random distribution", "Shape of the timing randomness. Log-normal matches real typing best.", s, "Variation", .custom, "lognormal",
                 [("lognormal", "Log-normal"), ("gaussian", "Gaussian"), ("uniform", "Uniform")]),
            num(K.driftAmount, "Speed drift", "Slow wandering of overall speed over time (like getting into a flow, then slowing down).", s, "Variation", .advanced, 12, 0, 60, 1, "%", human: (0, 25)),
            num(K.driftPeriod, "Speed drift period", "How long a drift cycle takes.", s, "Variation", .custom, 40, 5, 600, 1, "s"),
            num(K.minKeyDelay, "Fastest single keystroke", "No keystroke will ever be faster than this.", s, "Limits", .advanced, 25, 1, 500, 1, "ms"),
            num(K.maxKeyDelay, "Slowest single keystroke", "No keystroke (excluding pauses) will be slower than this.", s, "Limits", .advanced, 900, 50, 5000, 10, "ms"),
            num(K.holdMin, "Key hold time (min)", "How long each key is held down, minimum.", s, "Key press", .custom, 35, 1, 300, 1, "ms"),
            num(K.holdMax, "Key hold time (max)", "How long each key is held down, maximum.", s, "Key press", .custom, 95, 1, 400, 1, "ms"),
            num(K.shiftPenalty, "Shifted keys slower by", "Extra time for capital letters and shifted symbols.", s, "Hard keys", .advanced, 35, 0, 300, 1, "%", human: (0, 60)),
            num(K.numberRowPenalty, "Number row slower by", "Extra time for keys on the number row.", s, "Hard keys", .advanced, 25, 0, 300, 1, "%", human: (0, 45)),
            num(K.symbolPenalty, "Symbols slower by", "Extra time for punctuation and symbol keys like [ ] \\ ; ' / `.", s, "Hard keys", .advanced, 30, 0, 300, 1, "%", human: (0, 55)),
            num(K.unicodePenalty, "Special characters slower by", "Extra time for characters not on the keyboard (emoji, accents, other alphabets).", s, "Hard keys", .advanced, 150, 0, 1000, 5, "%", human: (0, 250)),
            num(K.sameFingerPenalty, "Same finger twice slower by", "Extra time when two keys in a row use the same finger.", s, "Finger model", .custom, 30, 0, 200, 1, "%", human: (0, 50)),
            num(K.sameKeyRepeat, "Same key twice", "Timing for pressing the same key twice (e.g. 'll'). Below 100% is faster.", s, "Finger model", .custom, 85, 20, 200, 1, "%"),
            num(K.handAlternation, "Alternating hands faster by", "Speed-up when consecutive keys use opposite hands.", s, "Finger model", .custom, 15, 0, 60, 1, "%", human: (0, 25)),
            num(K.rowJumpPenalty, "Row jump penalty", "Extra time per keyboard row the finger has to travel.", s, "Finger model", .custom, 8, 0, 60, 1, "%", human: (0, 15)),
            num(K.capitalAfterSpace, "Capital after space slower by", "Extra delay before a capital letter that starts a word.", s, "Hard keys", .custom, 20, 0, 200, 1, "%", human: (0, 40)),
            num(K.bigramBurst, "Common letter pair speed", "Speed of common letter pairs like 'th', 'er', 'in' (from the word list). Below 100% is faster.", s, "Bursts", .advanced, 75, 20, 120, 1, "%", human: (100, 65)),
            num(K.bigramBurstChance, "Common letter pair burst chance", "How often a common pair gets the speed-up.", s, "Bursts", .custom, 85, 0, 100, 1, "%"),
            num(K.wordBurst, "Common word speed", "Speed of very common words like 'the', 'and', 'you'. Below 100% is faster.", s, "Bursts", .advanced, 70, 20, 120, 1, "%", human: (100, 60)),
            num(K.wordBurstChance, "Common word burst chance", "How often a common word gets the speed-up.", s, "Bursts", .custom, 80, 0, 100, 1, "%"),
            num(K.randomBurstChance, "Random burst chance", "Chance per word of a random fast streak.", s, "Bursts", .advanced, 8, 0, 100, 1, "%", human: (0, 15)),
            num(K.randomBurstMult, "Random burst speed", "Speed during a random burst. Below 100% is faster.", s, "Bursts", .custom, 70, 20, 100, 1, "%"),
            num(K.randomBurstLength, "Random burst length", "How many characters a random burst lasts.", s, "Bursts", .custom, 12, 2, 200, 1, "chars"),
            num(K.warmupSeconds, "Warm-up time", "Typing starts a bit slower and speeds up over this time.", s, "Warm-up & fatigue", .advanced, 20, 0, 600, 1, "s", human: (0, 30)),
            num(K.warmupMult, "Warm-up start speed", "How slow typing starts (as % of normal time; above 100% is slower).", s, "Warm-up & fatigue", .custom, 130, 100, 300, 1, "%"),
            num(K.fatiguePerMinute, "Fatigue per minute", "Typing gets this much slower every minute.", s, "Warm-up & fatigue", .advanced, 0.6, 0, 10, 0.1, "%", human: (0, 1.2)),
            num(K.fatigueMax, "Maximum fatigue", "Fatigue slowdown never exceeds this.", s, "Warm-up & fatigue", .custom, 25, 0, 200, 1, "%"),
        ]
        let fingerDefaults: [Double] = [118, 108, 100, 95, 95, 100, 108, 118, 90]
        for (i, name) in fingerNames.enumerated() {
            d.append(num(K.finger(i), "\(name) speed", "Time multiplier for keys pressed by the \(name.lowercased()). Above 100% is slower.", s, "Per-finger speed", .custom, fingerDefaults[i], 30, 300, 1, "%"))
        }
        let rowDefaults: [Double] = [112, 102, 95, 105, 90]
        for (i, name) in rowNames.enumerated() {
            d.append(num(K.row(i), "\(name) speed", "Time multiplier for keys on the \(name.lowercased()). Above 100% is slower.", s, "Per-row speed", .custom, rowDefaults[i], 30, 300, 1, "%"))
        }

        // MARK: Rhythm
        let r = SettingTab.rhythm
        d += [
            num(K.pauseSpace, "Pause after a space", "Average extra time after typing a space.", r, "Punctuation pauses", .advanced, 40, 0, 2000, 5, "ms", human: (0, 70)),
            num(K.pauseComma, "Pause after a comma", "Average extra time after a comma.", r, "Punctuation pauses", .advanced, 220, 0, 5000, 10, "ms", human: (0, 380)),
            num(K.pausePeriod, "Pause after a period", "Average extra time after ending a sentence.", r, "Punctuation pauses", .simple, 450, 0, 10000, 10, "ms", human: (0, 800)),
            num(K.pauseQuestion, "Pause after ? or !", "Average extra time after a question mark or exclamation point.", r, "Punctuation pauses", .advanced, 500, 0, 10000, 10, "ms", human: (0, 850)),
            num(K.pauseColon, "Pause after : or ;", "Average extra time after a colon or semicolon.", r, "Punctuation pauses", .custom, 300, 0, 5000, 10, "ms", human: (0, 500)),
            num(K.pauseDash, "Pause around dashes", "Average extra time after - – —.", r, "Punctuation pauses", .custom, 150, 0, 5000, 10, "ms", human: (0, 260)),
            num(K.pauseQuote, "Pause after closing quotes", "Average extra time after a closing quote.", r, "Punctuation pauses", .custom, 120, 0, 5000, 10, "ms", human: (0, 200)),
            num(K.pauseBracket, "Pause after brackets", "Average extra time after ) ] }.", r, "Punctuation pauses", .custom, 120, 0, 5000, 10, "ms", human: (0, 200)),
            num(K.pauseNewline, "Pause after a new line", "Average extra time after pressing Return.", r, "Line pauses", .simple, 700, 0, 20000, 10, "ms", human: (0, 1200)),
            num(K.pauseParagraph, "Pause after a paragraph", "Extra time after a blank line (new paragraph).", r, "Line pauses", .advanced, 1800, 0, 60000, 50, "ms", human: (0, 3200)),
            num(K.pauseJitter, "Pause randomness", "How much punctuation and line pauses vary.", r, "Line pauses", .custom, 45, 0, 150, 1, "%"),
            num(K.wordStartMult, "Word start delay", "Extra time before the first letter of each word.", r, "Words", .custom, 15, 0, 300, 1, "%", human: (0, 30)),
            num(K.longWordLength, "Long word length", "Words with at least this many letters count as long.", r, "Words", .custom, 9, 4, 30, 1, "letters"),
            num(K.longWordPause, "Pause before long words", "Extra time before starting a long word.", r, "Words", .advanced, 180, 0, 5000, 10, "ms", human: (0, 350)),
            num(K.rareWordChance, "Unfamiliar word pause chance", "Chance of a short pause before a word that isn't in the common word list.", r, "Words", .custom, 20, 0, 100, 1, "%", human: (0, 35)),
            num(K.rareWordPause, "Unfamiliar word pause", "Length of that pause.", r, "Words", .custom, 250, 0, 5000, 10, "ms", human: (0, 400)),
            num(K.numberSlowdown, "Numbers slower by", "Extra time while typing digits inside numbers.", r, "Words", .custom, 20, 0, 300, 1, "%", human: (0, 35)),
            num(K.capsWordSlowdown, "ALL CAPS words slower by", "Extra time while typing words in all capitals.", r, "Words", .custom, 25, 0, 300, 1, "%", human: (0, 45)),
            tog(K.thinkEnabled, "Thinking pauses", "Occasional longer pauses like you're thinking about what to write next.", r, "Thinking pauses", .simple, true),
            num(K.thinkChanceWord, "Thinking pause chance per word", "Chance of a thinking pause before any word.", r, "Thinking pauses", .simple, 2, 0, 100, 0.5, "%", human: (0, 4), dep: K.thinkEnabled),
            num(K.thinkChanceSentence, "Thinking pause chance per sentence", "Chance of a thinking pause at the start of a sentence.", r, "Thinking pauses", .advanced, 12, 0, 100, 1, "%", human: (0, 22), dep: K.thinkEnabled),
            num(K.thinkChanceParagraph, "Thinking pause chance per paragraph", "Chance of a thinking pause at the start of a paragraph.", r, "Thinking pauses", .advanced, 40, 0, 100, 1, "%", human: (0, 65), dep: K.thinkEnabled),
            num(K.thinkMin, "Thinking pause shortest", "Shortest thinking pause.", r, "Thinking pauses", .advanced, 1.0, 0.1, 120, 0.1, "s", dep: K.thinkEnabled),
            num(K.thinkMax, "Thinking pause longest", "Longest thinking pause.", r, "Thinking pauses", .advanced, 4.5, 0.1, 600, 0.1, "s", dep: K.thinkEnabled),
            num(K.hesitationChance, "Mid-word hesitation chance", "Chance per word of a tiny stall in the middle of the word.", r, "Hesitations", .custom, 4, 0, 100, 0.5, "%", human: (0, 8)),
            num(K.hesitationMin, "Hesitation shortest", "", r, "Hesitations", .custom, 150, 0, 5000, 10, "ms"),
            num(K.hesitationMax, "Hesitation longest", "", r, "Hesitations", .custom, 600, 0, 10000, 10, "ms"),
            num(K.rereadChance, "Re-read pause chance", "Chance after each sentence of pausing to re-read what you wrote.", r, "Hesitations", .custom, 6, 0, 100, 1, "%", human: (0, 12)),
            num(K.rereadMin, "Re-read pause shortest", "", r, "Hesitations", .custom, 1.5, 0.1, 60, 0.1, "s"),
            num(K.rereadMax, "Re-read pause longest", "", r, "Hesitations", .custom, 5, 0.1, 120, 0.1, "s"),
            tog(K.breakEnabled, "Take breaks on long runs", "Occasional long breaks during long typing sessions.", r, "Breaks", .advanced, false),
            num(K.breakChancePerMinute, "Break chance per minute", "Chance each minute of taking a break.", r, "Breaks", .advanced, 3, 0, 100, 0.5, "%", dep: K.breakEnabled),
            num(K.breakMin, "Break shortest", "", r, "Breaks", .advanced, 15, 1, 3600, 1, "s", dep: K.breakEnabled),
            num(K.breakMax, "Break longest", "", r, "Breaks", .advanced, 90, 1, 7200, 1, "s", dep: K.breakEnabled),
            num(K.breakMinGap, "Minimum time between breaks", "", r, "Breaks", .custom, 4, 0.5, 120, 0.5, "min", dep: K.breakEnabled),
        ]

        // MARK: Typos
        let t = SettingTab.typos
        d += [
            tog(K.typosEnabled, "Make typos", "Make realistic mistakes and fix them like a person would.", t, "Typos", .simple, true),
            num(K.typoMaster, "Typo amount", "Scales every typo type at once. 100% uses the individual chances as-is.", t, "Typos", .simple, 100, 0, 400, 5, "%", human: (0, 180), dep: K.typosEnabled),
            tog(K.safeTypoMode, "Safe typo mode", "Every typo is fixed before the word ends, so autocorrect (Word, Docs, browsers) never sees it. Turns off late fixes and unfixed typos.", t, "Typos", .simple, false, dep: K.typosEnabled),
            pick(K.autocorrectProtection, "Autocorrect protection", "macOS autocorrect can change a typo on its own before Handwritten fixes it, which throws off later fixes. Auto uses safe typos whenever your Mac's autocorrect is on.", t, "Typos", .simple, "auto",
                 [("auto", "Auto (when Mac autocorrect is on)"), ("on", "Always"), ("off", "Off")], dep: K.typosEnabled),
            tog(K.autocorrectReminder, "Remind me to turn off autocorrect", "Shows a reminder when 'Typing into' is set to Word.", t, "Typos", .advanced, true),
            num(K.typoNeighbor, "Neighbor key", "Hitting a key next to the right one (QWERTY map). Chance per letter.", t, "Typo types (chance per character)", .advanced, 1.6, 0, 20, 0.1, "%", dep: K.typosEnabled),
            num(K.typoDiagonalWeight, "Neighbor: diagonal keys", "How likely a neighbor typo hits a diagonal key versus one directly beside it.", t, "Typo types (chance per character)", .custom, 50, 0, 200, 5, "%", dep: K.typosEnabled),
            num(K.typoTranspose, "Swapped letters", "Typing two letters in the wrong order ('teh').", t, "Typo types (chance per character)", .advanced, 0.6, 0, 20, 0.1, "%", dep: K.typosEnabled),
            num(K.typoDouble, "Doubled letter", "Pressing a key twice ('thhe').", t, "Typo types (chance per character)", .advanced, 0.4, 0, 20, 0.1, "%", dep: K.typosEnabled),
            num(K.typoSkip, "Skipped letter", "Missing a letter ('th' for 'the').", t, "Typo types (chance per character)", .advanced, 0.5, 0, 20, 0.1, "%", dep: K.typosEnabled),
            num(K.typoShift, "Wrong capitalization", "Forgetting Shift or pressing it by accident.", t, "Typo types (chance per character)", .advanced, 0.3, 0, 20, 0.1, "%", dep: K.typosEnabled),
            num(K.typoShiftHold, "Shift held too long", "Two capitals at the start of a word ('THe'). Chance per capitalized word.", t, "Typo types (chance per character)", .advanced, 2.5, 0, 50, 0.5, "%", dep: K.typosEnabled),
            num(K.typoFatFinger, "Fat finger", "Hitting the right key AND a neighbor at once.", t, "Typo types (chance per character)", .custom, 0.3, 0, 20, 0.1, "%", dep: K.typosEnabled),
            num(K.typoMirror, "Wrong hand", "Pressing the mirror-image key with the other hand (e.g. 'f' ↔ 'j').", t, "Typo types (chance per character)", .custom, 0.1, 0, 20, 0.1, "%", dep: K.typosEnabled),
            num(K.typoSpace, "Space mistakes", "Extra or missing space between words. Chance per word.", t, "Typo types (chance per character)", .custom, 0.8, 0, 20, 0.1, "%", dep: K.typosEnabled),
            num(K.typoPunct, "Punctuation slip", "Hitting a neighbor key on punctuation (e.g. '.' → ',').", t, "Typo types (chance per character)", .custom, 0.8, 0, 20, 0.1, "%", dep: K.typosEnabled),
            num(K.typoMisspell, "Common misspelling", "Spell the word like the misspellings list ('recieve'). Chance per matching word.", t, "Word-level typos", .advanced, 12, 0, 100, 1, "%", dep: K.typosEnabled),
            num(K.typoWrongWord, "Wrong word", "Start typing a similar wrong word, then delete it. Chance per word.", t, "Word-level typos", .advanced, 0.5, 0, 20, 0.1, "%", dep: K.typosEnabled),
            num(K.typoWordStartMult, "More typos at word start", "Typo chance multiplier on the first letter of a word.", t, "Where typos happen", .custom, 60, 0, 300, 5, "%", dep: K.typosEnabled),
            num(K.typoWordEndMult, "More typos at word end", "Typo chance multiplier on the last letter of a word.", t, "Where typos happen", .custom, 120, 0, 300, 5, "%", dep: K.typosEnabled),
            num(K.typoLongWordMult, "More typos in long words", "Typo chance multiplier inside long words.", t, "Where typos happen", .custom, 140, 0, 300, 5, "%", dep: K.typosEnabled),
            num(K.typoBurstMult, "More typos when typing fast", "Typo chance multiplier during speed bursts.", t, "Where typos happen", .custom, 150, 0, 400, 5, "%", dep: K.typosEnabled),
            num(K.typoFatigueMult, "More typos when tired", "Extra typo chance at maximum fatigue.", t, "Where typos happen", .custom, 50, 0, 400, 5, "%", dep: K.typosEnabled),
            num(K.typoMaxPerWord, "Max typos per word", "Never more than this many typos in one word.", t, "Limits", .advanced, 1, 1, 5, 1, "", dep: K.typosEnabled),
            num(K.typoMinGap, "Minimum characters between typos", "", t, "Limits", .custom, 6, 0, 200, 1, "chars", dep: K.typosEnabled),
            tog(K.typoSkipURLs, "No typos in links", "Never make typos inside URLs like https://example.com.", t, "Skip typos in", .advanced, true, dep: K.typosEnabled),
            tog(K.typoSkipEmails, "No typos in email addresses", "", t, "Skip typos in", .advanced, true, dep: K.typosEnabled),
            tog(K.typoSkipNumbers, "No typos in numbers", "Numbers, dates, prices and times are always typed correctly.", t, "Skip typos in", .advanced, true, dep: K.typosEnabled),
            tog(K.typoSkipCode, "No typos in code-like text", "Skip words with symbols like _ { } ( ) = < > / \\ or camelCase.", t, "Skip typos in", .advanced, true, dep: K.typosEnabled),
            tog(K.typoSkipAllCaps, "No typos in ALL CAPS words", "", t, "Skip typos in", .advanced, true, dep: K.typosEnabled),
            tog(K.typoSkipCapitalized, "No typos in capitalized names", "Skip words that start with a capital letter mid-sentence (likely names).", t, "Skip typos in", .custom, false, dep: K.typosEnabled),
            num(K.typoSkipShortWords, "No typos in words shorter than", "", t, "Skip typos in", .custom, 2, 0, 10, 1, "letters", dep: K.typosEnabled),
            num(K.typoSkipFirstWords, "No typos in the first words", "Type the first N words perfectly.", t, "Skip typos in", .custom, 3, 0, 100, 1, "words", dep: K.typosEnabled),
            tog(K.typoSkipNonLatin, "No typos in non-English letters", "Skip typos on characters that aren't on a US keyboard.", t, "Skip typos in", .custom, true, dep: K.typosEnabled),
        ]

        // MARK: Corrections
        let c = SettingTab.corrections
        d += [
            num(K.fixImmediateWeight, "Notice right away", "Relative weight: fix the typo immediately.", c, "When typos get noticed", .advanced, 45, 0, 100, 1, "", dep: K.typosEnabled),
            num(K.fixDelayedWeight, "Notice a few characters later", "Relative weight: keep typing a few characters, then backspace and fix.", c, "When typos get noticed", .advanced, 30, 0, 100, 1, "", dep: K.typosEnabled),
            num(K.fixDelayedMin, "A few characters: at least", "", c, "When typos get noticed", .custom, 1, 1, 20, 1, "chars", dep: K.typosEnabled),
            num(K.fixDelayedMax, "A few characters: at most", "", c, "When typos get noticed", .custom, 4, 1, 30, 1, "chars", dep: K.typosEnabled),
            num(K.fixEndOfWordWeight, "Notice at the end of the word", "Relative weight: finish the word, then go back.", c, "When typos get noticed", .advanced, 15, 0, 100, 1, "", dep: K.typosEnabled),
            num(K.fixLateWeight, "Notice much later (arrow keys)", "Relative weight: keep going for a while, then use the arrow keys to go back, fix it, and return to the end.", c, "When typos get noticed", .advanced, 10, 0, 100, 1, "", dep: K.typosEnabled),
            num(K.fixLateMin, "Much later: at least", "Characters typed before noticing.", c, "When typos get noticed", .custom, 6, 2, 300, 1, "chars", dep: K.typosEnabled),
            num(K.fixLateMax, "Much later: at most", "", c, "When typos get noticed", .custom, 30, 2, 500, 1, "chars", dep: K.typosEnabled),
            num(K.leaveUnfixed, "Leave some typos unfixed", "Chance a typo is left in place. If 'Proofread at the end' is on, these get fixed at the end.", c, "Unfixed typos", .simple, 5, 0, 100, 1, "%", human: (0, 10), dep: K.typosEnabled),
            tog(K.proofreadAtEnd, "Proofread at the end", "When done, go back with the arrow keys and fix any typos that were left in.", c, "Unfixed typos", .simple, true, dep: K.typosEnabled),
            tog(K.verifyEnabled, "Check the text box at the end", "After typing, read the text box (or select all + copy) and compare it to what should be there, then fix any differences.", c, "End-of-run check", .simple, true),
            pick(K.verifyMethod, "How to read the text box", "Accessibility reads it directly without touching the clipboard. Select-all + copy works in more apps. Auto tries both.", c, "End-of-run check", .advanced, "auto",
                 [("auto", "Auto"), ("ax", "Accessibility only"), ("copy", "Select all + copy")], dep: K.verifyEnabled),
            num(K.verifyDelay, "Wait before checking", "Give the app time to finish updating before reading it.", c, "End-of-run check", .custom, 600, 0, 10000, 50, "ms", dep: K.verifyEnabled),
            num(K.verifyMaxFixes, "Maximum fixes", "If more differences than this are found, assume the cursor moved and don't touch anything.", c, "End-of-run check", .advanced, 40, 1, 1000, 1, "", dep: K.verifyEnabled),
            num(K.verifyMinSimilarity, "Minimum match", "Only fix if at least this much of the text is already right.", c, "End-of-run check", .custom, 70, 50, 100, 1, "%", dep: K.verifyEnabled),
            tog(K.verifyIgnoreSmartQuotes, "Ignore smart quotes and line-break styles", "Treat “ ” and \" as the same, and different line-break characters as the same.", c, "End-of-run check", .custom, true, dep: K.verifyEnabled),
            num(K.verifySpeed, "Check fix speed", "Typing speed while fixing differences at the end (% of normal time).", c, "End-of-run check", .custom, 90, 20, 300, 5, "%", dep: K.verifyEnabled),
            num(K.noticeMin, "Noticing delay (min)", "Pause after a typo before starting to fix it.", c, "How fixes look", .advanced, 180, 0, 5000, 10, "ms", human: (0, 320)),
            num(K.noticeMax, "Noticing delay (max)", "", c, "How fixes look", .advanced, 650, 0, 10000, 10, "ms", human: (0, 1000)),
            num(K.backspaceSpeed, "Backspace speed", "Time per backspace as % of normal typing (below 100% = faster).", c, "How fixes look", .advanced, 55, 10, 300, 5, "%"),
            num(K.backspaceVariation, "Backspace variation", "", c, "How fixes look", .custom, 25, 0, 150, 5, "%"),
            num(K.wordDeleteChance, "Delete whole word with ⌥⌫", "Chance of deleting the whole word at once (Option-Backspace) instead of letter by letter.", c, "How fixes look", .custom, 15, 0, 100, 1, "%"),
            num(K.wordDeleteMinChars, "Whole-word delete if at least", "Only delete the whole word if this many letters need to go.", c, "How fixes look", .custom, 4, 2, 30, 1, "chars"),
            num(K.overDeleteChance, "Over-delete chance", "Chance of backspacing a bit too far, then retyping.", c, "How fixes look", .custom, 12, 0, 100, 1, "%", human: (0, 20)),
            num(K.overDeleteMax, "Over-delete at most", "", c, "How fixes look", .custom, 2, 1, 10, 1, "chars"),
            num(K.typoWhileFixing, "Typo while fixing", "Chance of making another (immediately fixed) typo while retyping.", c, "How fixes look", .custom, 5, 0, 100, 1, "%", human: (0, 10)),
            num(K.retypeSlowdown, "Retyping slower by", "Retyping after a fix is a little more careful.", c, "How fixes look", .custom, 15, 0, 200, 5, "%"),
            num(K.pauseAfterFix, "Pause after a fix", "Short pause after finishing a correction.", c, "How fixes look", .custom, 150, 0, 5000, 10, "ms"),
            num(K.arrowSpeed, "Arrow key speed", "Time per arrow press when going back to fix something (% of normal typing).", c, "Arrow-key fixes", .custom, 60, 5, 300, 5, "%"),
            num(K.proofreadArrowSpeed, "Proofread arrow speed", "Time per arrow press during the end proofread.", c, "Arrow-key fixes", .custom, 35, 5, 500, 5, "ms"),
        ]

        // MARK: Text handling
        let x = SettingTab.text
        d += [
            pick(K.newlineMode, "New lines are typed as", "Shift+Return is safest in chat apps (Return might send the message). Return makes real paragraphs in Word.", x, "Keys", .simple, "shiftReturn",
                 [("shiftReturn", "Shift + Return"), ("return", "Return")]),
            pick(K.tabMode, "Tabs are typed as", "", x, "Keys", .simple, "tab", [("tab", "Tab key"), ("spaces", "Spaces")]),
            num(K.tabSpaces, "Spaces per tab", "", x, "Keys", .advanced, 4, 1, 16, 1, "spaces"),
            pick(K.keyMethod, "Key method", "Real keys sends actual key presses (best for most apps, VMs and remote desktops). Unicode only sends every character as text.", x, "Keys", .custom, "keys",
                 [("keys", "Real keys when possible"), ("unicode", "Unicode only")]),
            tog(K.codeMode, "Code editor mode", "Handles auto-indent and auto-closing brackets in VS Code, Xcode, etc. For perfect results, also turn off auto-closing brackets in your editor.", x, "Code editors", .simple, false),
            pick(K.codeIndentMode, "Auto-indent handling", "Clear: remove the editor's indent after each new line and type the original. Strip: don't type leading spaces; let the editor indent.", x, "Code editors", .advanced, "clear",
                 [("clear", "Clear editor indent, type original"), ("strip", "Let the editor indent"), ("off", "Do nothing")], dep: K.codeMode),
            pick(K.codeAutoCloseMode, "Auto-closed brackets", "Overtype: rely on the editor typing over its own closing bracket. Forward-delete: delete the auto-inserted closer right away (only safe when typing at the end of a file).", x, "Code editors", .advanced, "overtype",
                 [("overtype", "Overtype (default)"), ("forwardDelete", "Forward-delete after openers"), ("off", "Do nothing")], dep: K.codeMode),
            pick(K.doubleSpaceGuard, "Protect double spaces", "macOS turns two spaces after a word into \". \" (System Settings → Keyboard → \"Add period with double-space\"). This types extra spaces in a way that avoids it. Auto does this only when that Mac setting is on.", x, "Keys", .advanced, "auto",
                 [("auto", "Auto"), ("on", "Always"), ("off", "Off")]),
            tog(K.smartQuotesToStraight, "Convert smart quotes to straight", "Type “ ” ‘ ’ as \" and '.", x, "Clean-up", .advanced, false),
            tog(K.trimTrailingWhitespace, "Remove spaces at line ends", "", x, "Clean-up", .advanced, false),
            tog(K.trimEnds, "Trim start and end of text", "Remove blank lines and spaces at the very beginning and end.", x, "Clean-up", .advanced, false),
            tog(K.collapseBlankLines, "Collapse multiple blank lines", "", x, "Clean-up", .custom, false),
            tog(K.nbspToSpace, "Non-breaking spaces → spaces", "", x, "Clean-up", .custom, true),
            tog(K.stripZeroWidth, "Remove invisible characters", "Remove zero-width spaces and similar hidden characters.", x, "Clean-up", .custom, true),
            num(K.maxChars, "Maximum characters per run", "Safety limit. 0 = no limit.", x, "Limits", .custom, 0, 0, 1_000_000, 100, "chars"),
        ]

        // MARK: Clipboard
        let cb = SettingTab.clipboard
        d += [
            num(K.historySize, "History size", "How many recent clipboard items to keep (pinned items don't count).", cb, "History", .simple, 3, 1, 100, 1, "items"),
            tog(K.clearOnQuit, "Clear history on quit", "", cb, "History", .simple, false),
            tog(K.historyInMenu, "Show history in the menu bar menu", "", cb, "History", .advanced, true),
            tog(K.pinsEnabled, "Allow pinning items", "Pinned items stay in history until you unpin them.", cb, "History", .advanced, true),
            tog(K.ignoreDuplicates, "Ignore duplicates", "Copying the same text again moves it to the top instead of adding a copy.", cb, "History", .advanced, true),
            num(K.previewLength, "Preview length", "How much of the clipboard to show in the control panel preview.", cb, "Preview", .advanced, 400, 40, 5000, 20, "chars"),
            num(K.menuPreviewLength, "Menu preview length", "", cb, "Preview", .custom, 40, 10, 200, 5, "chars"),
            tog(K.skipPasswordManagers, "Skip password managers", "Don't save anything copied from 1Password, Bitwarden, Keychain, Passwords, etc.", cb, "Privacy", .simple, true),
            tog(K.skipConcealed, "Skip hidden/secret clipboard items", "Respect apps that mark copied data as concealed or temporary.", cb, "Privacy", .advanced, true),
            num(K.minLength, "Ignore items shorter than", "", cb, "Filters", .custom, 1, 1, 100, 1, "chars"),
            num(K.maxItemLength, "Ignore items longer than", "", cb, "Filters", .custom, 200_000, 100, 2_000_000, 100, "chars"),
            num(K.pollInterval, "Clipboard check interval", "How often to look for new clipboard contents.", cb, "Filters", .custom, 400, 100, 5000, 50, "ms"),
        ]

        // MARK: Hotkeys
        let h = SettingTab.hotkeys
        d += [
            tog(K.hkEnabled, "Global hotkeys", "Use keyboard shortcuts from any app.", h, "Hotkeys", .simple, true),
            txt(K.hkStart, "Start", "Start typing the clipboard.", h, "Hotkeys", .simple, HotkeyCombo.defaultStart.storage, kind: .hotkey, dep: K.hkEnabled),
            txt(K.hkPause, "Pause / Resume", "", h, "Hotkeys", .simple, HotkeyCombo.defaultPause.storage, kind: .hotkey, dep: K.hkEnabled),
            tog(K.hkPauseEnabled, "Pause/Resume hotkey enabled", "", h, "Hotkeys", .advanced, true, dep: K.hkEnabled),
            txt(K.hkStop, "Stop", "Escape also stops (see General).", h, "Hotkeys", .simple, HotkeyCombo.defaultStop.storage, kind: .hotkey, dep: K.hkEnabled),
            txt(K.hkMask, "Mask (hide/show everything)", "", h, "Hotkeys", .simple, HotkeyCombo.defaultMask.storage, kind: .hotkey, dep: K.hkEnabled),
            txt(K.hkPanel, "Open control panel", "", h, "Hotkeys", .advanced, HotkeyCombo.defaultPanel.storage, kind: .hotkey, dep: K.hkEnabled),
        ]

        // MARK: Mask
        let m = SettingTab.mask
        d += [
            tog(K.maskDummyIcon, "Show a dummy menu bar icon while masked", "A plain icon that looks like a system item. Clicking it unhides Handwritten.", m, "Mask", .simple, false),
            pick(K.maskDummyStyle, "Dummy icon look", "", m, "Mask", .advanced, "circle",
                 [("circle", "Dot"), ("wifi", "Wi-Fi style"), ("battery", "Battery style"), ("cloud", "Cloud"), ("clock", "Clock"), ("gear", "Gear")], dep: K.maskDummyIcon),
            tog(K.maskRequireOption, "Require ⌥-click to unhide", "Regular clicks on the dummy icon do nothing.", m, "Mask", .advanced, false, dep: K.maskDummyIcon),
            tog(K.maskStopsTyping, "Stop typing when masking", "Off = typing keeps going while hidden.", m, "Mask", .advanced, false),
            tog(K.maskOnLaunch, "Start masked", "Launch already hidden (use the hotkey to show).", m, "Mask", .custom, false),
        ]

        // MARK: Appearance
        let a = SettingTab.appearance
        d += [
            pick(K.theme, "Theme", "", a, "Theme", .simple, "system", [("system", "System"), ("light", "Light"), ("dark", "Dark")]),
            pick(K.accent, "Accent color", "", a, "Theme", .simple, "blue",
                 [("blue", "Blue"), ("purple", "Purple"), ("pink", "Pink"), ("red", "Red"), ("orange", "Orange"), ("yellow", "Yellow"), ("green", "Green"), ("graphite", "Graphite"), ("custom", "Custom")]),
            txt(K.customAccent, "Custom accent color", "Pick any color.", a, "Theme", .simple, "#5B8CFF", kind: .color),
            pick(K.menuIcon, "Menu bar icon", "", a, "Menu bar", .advanced, "pencil.line",
                 [("pencil.line", "Pencil"), ("keyboard", "Keyboard"), ("character.cursor.ibeam", "Cursor"), ("signature", "Signature"), ("text.cursor", "Text")]),
            tog(K.colorIconWhenTyping, "Color the icon while typing", "", a, "Menu bar", .advanced, true),
            num(K.hudOpacity, "Progress bar opacity", "", a, "Progress bar", .advanced, 95, 20, 100, 1, "%"),
            num(K.hudScale, "Progress bar size", "", a, "Progress bar", .custom, 100, 60, 200, 5, "%"),
        ]

        // MARK: Developer
        let dv = SettingTab.developer
        d += [
            tog(K.useSeed, "Use a fixed seed", "Same settings + same seed + same text = exactly the same typing, every time. For testing.", dv, "Randomness", .custom, false),
            num(K.seed, "Seed", "", dv, "Randomness", .custom, 12345, 0, 999_999_999, 1, "", dep: K.useSeed),
            tog(K.dryRun, "Dry run (don't send keys)", "Plans and times the run but doesn't actually type. For testing timing.", dv, "Testing", .custom, false),
            tog(K.logPlan, "Log the keystroke plan", "Writes the planned keystrokes to ~/Library/Application Support/Handwritten/last-plan.txt.", dv, "Testing", .custom, false),
            num(K.timingCompensation, "Timing compensation", "Corrects for system timer lateness to keep the ETA accurate.", dv, "Timing", .custom, 100, 0, 100, 5, "%"),
        ]

        return d
    }
}
