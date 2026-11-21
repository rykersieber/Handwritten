import AppKit

/// Debug: renders the app's own windows to PNGs (no screen-recording permission needed).
/// Run: open -n --env HW_RENDER=/path/to/dir Handwritten.app
@MainActor
enum RenderSnapshots {
    static func run(dir: String) {
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        Task { @MainActor in
            let wm = WindowManager.shared
            let app = AppDelegate.shared!
            let store = SettingsStore.shared
            let savedLevel = store.uiLevel

            app.showControlPanel()
            await pause(1.2)
            snap(wm.window(.controlPanel), out.appendingPathComponent("control-panel.png"))

            app.showOnboarding()
            await pause(0.8)
            snap(wm.window(.onboarding), out.appendingPathComponent("onboarding.png"))
            wm.close(.onboarding)

            AppState.shared.runState = .typing
            AppState.shared.charsTotal = 420; AppState.shared.charsDone = 173; AppState.shared.secondsRemaining = 95
            wm.showHUD(.hud, size: NSSize(width: 300, height: 74)) { ProgressHUDView().themed() }
            await pause(0.8)
            snap(wm.window(.hud), out.appendingPathComponent("hud.png"))
            AppState.shared.runState = .idle
            wm.close(.hud)

            for (level, tabs) in [(SettingLevel.simple, [SettingTab.general, .speed, .typos]),
                                  (.advanced, [.corrections, .rhythm]),
                                  (.custom, [.speed, .presets, .hotkeys, .developer])] {
                store.uiLevel = level
                for tab in tabs {
                    app.showSettings(tab: tab)
                    await pause(1.0)
                    snap(wm.window(.settings), out.appendingPathComponent("settings-\(level.title.lowercased())-\(tab.rawValue).png"))
                }
            }
            store.uiLevel = savedLevel

            // Personalize: intro, typing (half done), results (from a simulated typist).
            for phase in ["intro", "typing", "results"] {
                let m = PersonalizeModel()
                let sample = m.sample
                var vals = store.snapshot.values
                vals[K.useSeed] = .bool(true); vals[K.autocorrectProtection] = .text("off")
                let plan = Planner.makePlan(text: sample, settings: SettingsSnapshot(values: vals), words: WordData.shared.snapshot())
                if phase == "typing" {
                    m.phase = .typing
                    m.typed = String(sample.prefix(sample.count / 2)).replacingOccurrences(of: "learn", with: "lrean")
                    m.keys = Array(TypingAnalyzer.keys(from: plan).prefix(plan.steps.count / 2))
                } else if phase == "results" {
                    m.keys = TypingAnalyzer.keys(from: plan)
                    m.typed = String(plan.finalModel)
                    m.analysis = TypingAnalyzer.analyze(keys: m.keys, sample: sample, finalText: m.typed,
                                                        base: store.snapshot, words: WordData.shared.snapshot())
                    m.phase = .results
                }
                wm.destroy(.personalize)
                wm.show(.personalize, title: "Personalize", size: NSSize(width: 720, height: 640), resizable: true, floating: false) {
                    PersonalizeView(model: m).themed()
                }
                await pause(1.2)
                snap(wm.window(.personalize), out.appendingPathComponent("personalize-\(phase).png"))
            }
            exit(0)
        }
    }

    private static func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }

    private static func snap(_ w: NSWindow?, _ url: URL) {
        guard let w, let view = w.contentView?.superview ?? w.contentView else { return }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
    }
}
