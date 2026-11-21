# Handwritten — Full Spec & Build Status

> **For any AI or developer picking this up:** this file is the single source of truth.
> Read it fully before writing code. Update the **Status** checkboxes and the **Build Log**
> at the bottom every time you finish something. Do not remove requirements; if one is
> changed, strike it through and note why.

---

## 1. What the app is

**Handwritten** is a macOS menu bar app that *types out* whatever is in the clipboard
(simulated keystrokes) instead of pasting it, in a way that looks like a real human typing.
It is extremely customizable: speed, rhythm, pauses, typos, corrections, and a "humanness"
master slider.

- Platform: macOS 14.0+ (developed on macOS 26.3.1, Xcode 26.4, Swift 6.3 toolchain in Swift 5 language mode)
- UI: AppKit (`NSStatusItem`, `NSPanel`) hosting SwiftUI views
- Project generated with **XcodeGen** from `project.yml` → run `xcodegen generate` after adding/removing files
- No App Sandbox (required to post keyboard events). Hardened runtime on.
- Distribution: built in Xcode with free Personal Team signing, OR ad-hoc signed zip on GitHub Releases (see §12)
- No third-party dependencies (hotkeys via Carbon `RegisterEventHotKey`, login item via `SMAppService`)

---

## 2. Project layout

```
Handwritten/
  project.yml                  XcodeGen config
  SPEC.md                      this file
  README.md                    user-facing install + usage
  scripts/release.sh           builds ad-hoc signed zip for GitHub
  .github/workflows/release.yml  optional CI release
  Handwritten/
    App/            HandwrittenApp.swift, AppDelegate.swift, AppState.swift
    MenuBar/        StatusBarController.swift
    Permissions/    PermissionsManager.swift, OnboardingView.swift
    Engine/         KeySender.swift, KeyMap.swift, Planner.swift, TypingEngine.swift,
                    TypingAction.swift, HumanModel.swift, TypoGenerator.swift,
                    Verifier.swift, InputMonitor.swift, SeededRandom.swift
    Clipboard/      ClipboardManager.swift, ClipboardItem.swift
    Settings/       Settings.swift (all values), SettingDescriptor.swift (registry for UI/search),
                    PresetStore.swift, BuiltInPresets.swift, SettingsView.swift (+ tab views)
    Hotkeys/        HotkeyManager.swift, HotkeyRecorderView.swift
    Windows/        WindowManager.swift, ControlPanelView.swift, ProgressHUDView.swift,
                    HistoryEditorView.swift
    Data/           common_words.txt, common_bigrams.txt, misspellings.txt,
                    qwerty_neighbors.json (bundled; copied to Application Support on first run, user-editable)
    Assets.xcassets
    Info.plist, Handwritten.entitlements
```

User data lives in `~/Library/Application Support/Handwritten/`:
`settings.json`, `presets/*.json`, `history.json`, `data/*.txt` (editable copies).

---

## 3. Core architecture

### 3.1 Plan-then-execute engine
1. On Start, the **Planner** takes the target text + settings + RNG (seeded or random) and produces
   an array of `TypingAction`s: `.type(char)`, `.key(special)`, `.backspace`, `.arrow(dir)`,
   `.wait(seconds)` — each with a precomputed delay.
2. Because the plan is precomputed, **total duration is known exactly** (sum of delays).
3. **Timer mode**: user gives a target duration; the planner builds a plan, then scales all
   delays (keeping min/max per-key clamps) to hit the target. Iterate if clamps distort it.
4. The **TypingEngine** executes actions on a background thread with a cursor index.
   - **Pause** = stop at the current index. **Resume** = countdown, then continue at the same index.
   - Actions are grouped into "atomic groups" (e.g. a typo + its fix). Default: pause mid-group,
     and on resume finish the group first. Toggle: *finish the fix before pausing*.
   - **Stop** = abort, reset.
5. Engine tracks a model of what it has typed (`typedBuffer` + caret position) at every step.

### 3.2 Sending keys (KeySender)
- ASCII / keys on the US QWERTY layout → real virtual keycodes via `CGEvent(keyboardEventSource:virtualKey:keyDown:)`
  with the Shift flag when needed (so apps see real key events).
- Anything else (emoji, accents, CJK, symbols) → `keyboardSetUnicodeString` on a keyDown/keyUp pair.
- Every synthetic event is tagged with `eventSourceUserData = 0x48574E` ("HWN") so the
  InputMonitor can tell our events from the user's.
- Key hold time (down→up) is a setting.

### 3.3 InputMonitor (CGEventTap, listen-only)
- Detects **Escape** (always stops — toggle, on by default).
- Detects user **mouse clicks** and **frontmost app changes** → auto-pause (toggle, on by default).
- Ignores everything during countdown. Mouse *movement* never pauses.
- Ignores events tagged with our marker.

### 3.4 End-of-run verification (toggle)
1. Try to read the focused element's text via Accessibility (`AXFocusedUIElement` → `kAXValueAttribute`).
2. Fallback: save clipboard → ⌘A, ⌘C → read → restore clipboard (not added to history) → collapse selection (→ / ⌘↓).
3. Locate our intended text within the document (diff, tolerant of pre-existing text).
4. Navigate with arrow keys and fix each mismatch at human speed; return caret to the end.
5. Deliberately-unfixed typos are corrected in this pass. It also catches autocorrect changes.

---

## 4. Menu bar

- Icon states: gray = idle, accent color = typing, yellow = paused, countdown number shown during countdown.
- Percentage text next to icon while running (toggle).
- Menu: Start / Pause–Resume / Stop, recent history (click = make it the clipboard; does **not** start),
  preset quick picker, Open Control Panel, Settings…, Quit.

## 5. Windows

- **Control Panel** (floating `NSPanel`, movable): clipboard preview (first N chars), history list
  (select / edit / pin / delete), "Typing into" quick picker (General / Browser / Word / Code Editor),
  preset picker, estimated duration, Start / Pause / Stop, button to open Settings.
- **Progress HUD** (floating, movable): progress bar, chars done / total, time remaining.
- **Settings** (movable, resizable, closable): tabs, search button → search field, Simple / Advanced / Custom mode switch.
- **History editor**: edit an entry's text before typing it.
- **Onboarding**: walks user through Accessibility + Input Monitoring permissions; detects if they were lost after an update.

## 6. Clipboard & history

- Polls `NSPasteboard.changeCount`. Plain text only; rich text (RTF/HTML) converted to plain string. Images/files ignored.
- Skips entries marked concealed/transient (`org.nspasteboard.ConcealedType`, `TransientType`, `AutoGeneratedType`)
  and entries copied from known password managers (1Password, Bitwarden, Keychain Access, Passwords, LastPass, Dashlane, KeePassXC…).
- History size adjustable (default 3). Persists across launches; toggle *clear on quit*.
- Pins: pinned items never fall out of history.
- Selecting a history item replaces the current clipboard; Start types the current clipboard.
- Edit an entry before typing.

## 7. Typing behavior (all adjustable)

### 7.1 Speed
- Modes: **WPM** (shows exact ETA) or **Timer** (enter target duration; app adjusts).
- Base WPM, variation %, min/max per-key delay clamps, key hold time, warm-up at start, fatigue over time.
- Hard-to-reach / shifted keys slower; same-finger penalty; per-finger speed multipliers.
- Bursts on common words/bigrams (from `common_words.txt`, `common_bigrams.txt`).

### 7.2 Rhythm & pauses
- Extra delay after: space, comma, period/!/?, colon/semicolon, newline, paragraph, before long/rare words.
- Thinking pauses: probability per word, min/max length, more likely at sentence/paragraph starts.
- Breaks for long runs: probability, length.

### 7.3 Typos (separate probability for each)
- Neighbor key (QWERTY map), transposition, doubled letter, skipped letter, Shift mistake
  (capitalization), wrong whole word, dictionary misspelling (`misspellings.txt`), extra space.
- Skip zones: URLs, emails, numbers, code-like tokens, ALL CAPS words (each toggleable).
- **Safe typo mode**: only typo types autocorrect is unlikely to "fix" itself.
- Autocorrect reminder (shown when "Typing into: Word" or toggle).

### 7.4 Corrections
- When noticed, with weights: immediately, a few chars later (range), end of word, much later
  (go back with arrow keys, fix, return with arrow keys / ⌘→ / ⌥→).
- Backspace style: char-by-char or ⌥⌫ whole word (probability), backspace speed multiplier,
  "noticing" delay, chance of over-deleting and retyping, chance of a typo while fixing.
- Chance to leave a typo unfixed (fixed later by verification pass if enabled).
- Final text must equal clipboard text unless the user explicitly disables verification and leaves typos unfixed.

### 7.5 Text handling
- Newline: Return or Shift+Return (default Shift+Return).
- Tab: Tab key or N spaces.
- **Code editor mode** (toggle): bracket/quote overtype handling; after each Return, clear
  editor-inserted indentation (⌘⇧← / ⌫ style) then type the exact original indent.
  Alternative option: strip leading whitespace and let the editor indent.
- Every Unicode character must be typeable.

### 7.6 Humanness master slider (0–100%)
- 0% = robot (constant speed, no typos, no pauses). 100% = sloppy distracted human.
- Scales variation, bursts, pauses, and typo rates along a curve. Settings the user changed
  manually (marked "overridden") are not scaled.

### 7.7 Randomness
- Seed (Custom mode only) for repeatable runs. Distribution choice (log-normal default / gaussian / uniform).

## 8. Settings UI

- Modes: **Simple** (~15 settings), **Advanced** (~80), **Custom** (all — hundreds).
- Every setting registered in `SettingDescriptor` registry: key, title, description, tab, section, min mode, type, range, default.
- Each setting: description, reset button, "changed" marker.
- Search across all settings (search button reveals field; jumps to setting).
- Tabs: General, Speed, Rhythm, Typos, Corrections, Text Handling, Clipboard, Hotkeys, Mask, Appearance, Presets, Developer (Custom only).
- Sliders AND number input for numeric settings.
- Data file editor (open words/typo files in app, or reveal in Finder).

## 9. Presets

- Built-in: Hunt & Peck, Casual, Average Student, Office Worker, Fast Typist, Pro Typist,
  Programmer, Careful Writer, Essay Thinker, Late-Night Tired, Chat Messenger, Instant.
- Save / load / rename / delete user presets (persisted). Import/export settings + presets as `.json` file.

## 10. Hotkeys (global, recordable)

| Action | Default |
|---|---|
| Start | ⌃⌥⌘S |
| Pause / Resume | ⌃⌥⌘P |
| Stop | ⌃⌥⌘X (+ Escape) |
| Mask toggle | ⌃⌥⌘H |
| Open control panel | ⌃⌥⌘O |
Pause/resume hotkey can be toggled on/off. Hotkeys must never corrupt typed text.

## 11. Mask mode

- One hotkey hides **everything**: Dock icon, ⌘-Tab, control panel, HUD, settings, menu bar icon.
- Typing continues while masked.
- Optional **dummy menu bar icon** (choose from generic system-looking glyphs); clicking it unhides
  (optional "require ⌥-click"). Same hotkey also unhides.
- Must still appear in Activity Monitor (no process hiding).

## 12. Appearance & system

- Light / Dark / System. Accent color picker (8 built-in + custom).
- Show Dock icon toggle (default off — menu bar app).
- Launch at login toggle (`SMAppService.mainApp`).

## 13. Distribution

- `scripts/release.sh`: `xcodebuild` Release → ad-hoc sign (`codesign -s - --deep --force -o runtime`) → zip → `dist/Handwritten-<version>.zip`.
- GitHub Actions workflow builds and attaches zip on tag `v*`.
- README explains Gatekeeper: Privacy & Security → Open Anyway, or `xattr -dr com.apple.quarantine /Applications/Handwritten.app`.
- Ad-hoc builds lose Accessibility/Input Monitoring on update → onboarding detects and guides re-grant.
- For local dev: project.yml sets DEVELOPMENT_TEAM (the owner's free Personal Team) + "Apple Development" identity, so
  macOS permissions persist across rebuilds. Build with:
  `xcodebuild -project Handwritten.xcodeproj -scheme Handwritten -configuration Debug -derivedDataPath build -allowProvisioningUpdates build`
  **Do NOT pass CODE_SIGN_IDENTITY="-"** for dev builds — ad-hoc signing changes identity every build and resets permissions.
  (release.sh intentionally ad-hoc signs for GitHub distribution.) Another developer must change DEVELOPMENT_TEAM to their own team.

## 14. Known limits
- Secure input fields (passwords) block synthetic typing (macOS design).
- Apps with aggressive autocorrect may alter text; verification pass + safe typo mode mitigate.

---

## STATUS

Legend: `[x]` done & builds · `[~]` partly done · `[ ]` not started

### Phase 1 — Skeleton
- [x] project.yml / XcodeGen project generates
- [x] App entry (`HandwrittenApp.swift`), AppDelegate, LSUIElement menu bar app
- [x] StatusBarController with icon states + percentage + countdown + menu
- [x] PermissionsManager + Onboarding window (re-grant help after updates)
- [x] WindowManager (floating panels, non-activating HUD, mask hide/restore)

### Phase 2 — Typing engine
- [x] KeySender (keycodes + Unicode fallback, event tagging, 20-UTF16 chunking)
- [x] KeyLayout (US QWERTY char→keycode+shift, finger, row, neighbors, mirror keys)
- [x] TypingAction / Step / TypingPlan
- [x] TypingEngine: countdown, start/pause/resume/stop, exact ETA via suffix sums, group-aware pause
- [x] InputMonitor: Escape stop, click/keypress/app-switch auto-pause (CGEventTap, NSEvent fallback)
- [x] Newline (Return / Shift+Return) / Tab (key / spaces), code editor mode (indent clear/strip, forward-delete auto-close)

### Phase 3 — Clipboard
- [x] ClipboardManager polling, RTF/HTML → plain text, images/files ignored, password manager + concealed-type skip
- [x] History persistence, size, pins, clear-on-quit, duplicates
- [x] Control panel preview + history list + editor ("Save & Use")

### Phase 4 — Human timing
- [x] WPM, variation (log-normal/gaussian/uniform), clamps, hold time
- [x] Bursts (word/bigram files, random bursts), hard keys, same-finger, hand alternation, row jumps, per-finger, per-row
- [x] Pauses: punctuation, newline/paragraph, thinking (word/sentence/paragraph), hesitation, reread, breaks, warm-up, fatigue, drift
- [x] Timer mode scaling (balanced / pauses-first / uniform) — verified exact

### Phase 5 — Typos & corrections
- [x] Typo types: neighbor, transpose, double, skip, shift, shift-hold, fat finger, mirror, space, punct, misspelling, wrong word
- [x] Skip zones: URLs, emails, numbers, code, ALL CAPS, capitalized, short words, first N words, non-Latin
- [x] Safe typo mode (fix before word ends), position/burst/fatigue multipliers, max per word, min gap
- [x] Fix timing: immediate / delayed / end of word / late with arrow keys (← fix →, or ⌘→)
- [x] Over-delete, ⌥⌫ word delete, typo-while-fixing, noticing delay, retype slowdown
- [x] Unfixed typos + end proofread (arrow keys)
- [x] Verifier: AX read (caret-aware) → ⌘A⌘C fallback (clipboard restored) → diff → fix with arrows; safety limits

### Phase 6 — Settings
- [x] Registry-driven settings (~230), Codable, persisted, "changed" markers, reset per setting / all
- [x] Settings window: sidebar tabs, search (⌘F), Simple/Advanced/Custom, sliders + number fields
- [x] Humanness master slider (curve through defaults; manual overrides respected)
- [x] Presets (12 built-in + user save/load/rename/update/delete), import/export JSON
- [x] Hotkeys (Carbon) + recorder

### Phase 7 — Mask, appearance, distribution
- [x] Mask mode + dummy icon (styles, ⌥-click option), typing continues while masked
- [x] Accent color (8 + custom) + theme, Dock toggle, launch at login (SMAppService)
- [x] Progress HUD (movable, opacity/size settings, pause/stop buttons)
- [x] Data files (1,100 words, 300 bigrams, 450+ misspelling lines) + in-app editor
- [x] scripts/release.sh, .github/workflows/release.yml, README

### Phase 8 — Testing
Debug modes (env vars, launch with `open -n --env NAME=value build/Build/Products/Debug/Handwritten.app` so the app owns its permissions):
- `HW_SELFTEST=1` (can run the binary directly): planner replay (1440 runs), end-of-run-check fix logic (7 cases), engine timing + pause/resume + stop (dry run). All pass.
- `HW_E2E=<dir>`: real tests → `<dir>/e2e-results.txt`. Settings/presets/clipboard/hotkeys/mask always; with Accessibility: 13 real typing cases in TextEdit (saved with ⌘S and compared from disk), sidebar clicks, Escape, key auto-pause + resume, app-switch auto-pause.
- `HW_RENDER=<dir>`: renders control panel, HUD, onboarding and settings tabs to PNGs.
- `HW_SHOW=panel|settings:<tab>|onboarding`: opens a window on launch.

- [x] Planner self-test (1440/1440)
- [x] End-of-run check fix logic (7/7) — fixed: alignment now uses DP with free leading text (never deletes pre-existing text); similarity = share of expected text already present (default min 70%)
- [x] Engine timing within 2% — fixed: deadline-based scheduling (holds inside next interval) + App Nap disabled while typing
- [x] Settings, humanness, presets, export/import, clipboard (RTF/HTML/concealed/images/history/pins/dupes/edit), hotkeys, mask — 34/34 E2E pass
- [x] UI renders checked (all windows) — fixed: sidebar now plain buttons (List selection didn't respond); app accent used everywhere instead of system accent; custom progress bar
- [x] App launches and stays running
- [x] E2E real typing — 78/78 pass. 13 engine cases in a built-in "Test Pad" (NSTextView with every macOS
      correction off) + 5 real-world TextEdit cases with the Mac's autocorrect/auto-capitalize/double-space-period ON
      + controller tests (start, HUD, Escape, key auto-pause, resume countdown, app-switch auto-pause) + UI click tests
      (sidebar, preset rows). Run: `open -n --env HW_E2E=<dir> build/.../Handwritten.app` (add HW_E2E_SKIP_TYPING=1 for UI only).
- [ ] Browser text fields (Safari/Chrome) — not yet automated
- [ ] Manual: Word (AutoCorrect on/off, verifier)
- [ ] Manual: VS Code (code editor mode)
- [ ] Manual: Emoji/Unicode in real apps
- [ ] Manual: pause/resume integrity, Escape, auto-pause, hotkeys, mask, dummy icon
- [x] App icon: notebook paper + ink "h" + text cursor, drawn by `swift scripts/make_icon.swift` (regenerates all sizes + icon.png)

### Personalize (learn my typing)
- [x] Personalize window (control panel button + menu item): pick a built-in sample (Everyday / School essay /
      Casual message / Work email) or use clipboard text; type it in a recorder box (all Mac corrections off,
      paste blocked); live progress with green/red per-character marking, live WPM, backspace count.
- [x] Recorder captures key-down time, key-up (hold), backspace/⌥⌫/arrows, auto-repeat.
- [x] TypingAnalyzer (Personalize/TypingAnalyzer.swift) learns ~30 settings: WPM, variation, pauses after
      space/comma/sentence end/colon/new line, re-read pauses, thinking pauses, capital/number/symbol slowdowns,
      common-pair/common-word bursts, key hold, typo amount, unfixed %, fix-timing weights, noticing delay,
      backspace speed, ⌥⌫ use, warm-up, fatigue.
- [x] Calibration: simulates the app typing the same text with the learned settings, measures it the same way,
      and adjusts typo amount + WPM until the simulation matches the user.
- [x] Results table (You vs Current) → "Use These Settings" saves + loads a user preset (default "My Typing").
- [x] Round-trip self-test: plan with known settings → analyzer → recovers WPM within 15%, pauses within 30%,
      typo amount within 35% (3 profiles pass).

### Known macOS interactions (handled)
- macOS autocorrect changes typos before Handwritten fixes them → "Autocorrect protection" (Typos tab, default Auto)
  forces safe typos (fixed before the word ends) when the Mac's autocorrect is on.
- "Add period with double-space" → "Protect double spaces" (Text Handling, default Auto) types extra spaces by
  inserting them before the first one (← then space), so the char before the cursor is never a space.
- ⌘→ only reaches the end of the *visible* line in wrapped text → removed; late fixes return with arrow keys only.
- Auto-capitalization can capitalize a lowercase first word; the end-of-run check fixes it.
- Apps add a trailing line break to copied text that the cursor can't pass → the end check never deletes trailing whitespace.

### Ideas / later
- Per-app automatic profiles (detect frontmost app) — currently a manual "Typing into" picker
- Non-QWERTY layouts

---

## BUILD LOG
(newest first — date, what changed, what's next)

- 2026-11-20 — Added Personalize (learn my typing): recorder, analyzer with simulation calibration, results →
  preset. Round-trip tests pass. Next: try it with real typing and tune.
- 2026-11-20 — Full real-typing E2E: 78/78. Fixed: countdown of 0 never started typing; ⌘→ return breaking in wrapped
  text (option removed); macOS autocorrect desyncing late fixes (new Autocorrect protection); double-space → period
  (new Protect double spaces). Preset rows clickable. Next: browser text field tests, app icon.
- 2026-11-20 — Added "Custom (my settings)" = no preset; editing a typing setting switches to it. Fixed end-of-run check deleting the final character when copied text has a trailing line break. Switched dev signing to Personal Team so permissions persist.
- 2026-11-20 — Testing pass: fixed settings sidebar clicks, verifier refusing small fixes / unsafe alignment, engine running ~70% slower than ETA, purple system accent leaking into UI, gray progress bars. Added SelfTest/E2E/Render debug modes. Next: grant Accessibility + Input Monitoring to the build and run HW_E2E for real typing.
- 2026-11-20 — All phases written. Builds clean (Xcode 26.4). Self-test passes. Next: manual testing in real apps, app icon.
- 2026-11-20 — Spec written. Project folder created. Starting Phase 1.
