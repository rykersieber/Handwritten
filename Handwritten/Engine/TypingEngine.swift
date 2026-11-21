import AppKit
import Combine

/// Executes a TypingPlan on a background thread with exact pause/resume.
final class TypingEngine: @unchecked Sendable {
    private let cond = NSCondition()
    private var plan: TypingPlan?
    private var suffix: [Double] = []
    private var index = 0
    private var pauseRequested = false
    private var paused = false
    private var stopRequested = false
    private var resumeSignal = false
    private var thread: Thread?
    private var finishFixBeforePause = false
    private var compensation = 1.0
    private let sender = KeySender()
    /// Keeps macOS from throttling our timers (App Nap) while typing.
    private var activity: NSObjectProtocol?

    /// Callbacks on main thread.
    var onProgress: ((Int, Int, Double) -> Void)?
    var onPaused: (() -> Void)?
    var onFinishedTyping: (() -> Void)?

    var isRunning: Bool { cond.lock(); defer { cond.unlock() }; return thread != nil }

    func configure(_ s: SettingsSnapshot) {
        sender.useUnicodeOnly = s.str(K.keyMethod) == "unicode"
        sender.newlineShift = s.str(K.newlineMode) == "shiftReturn"
        sender.dryRun = s.bool(K.dryRun)
        finishFixBeforePause = s.bool(K.finishFixBeforePause)
        compensation = s.pct(K.timingCompensation)
    }

    var keySender: KeySender { sender }

    func start(_ p: TypingPlan) {
        cond.lock()
        plan = p
        suffix = p.suffixDurations()
        index = 0
        pauseRequested = false
        paused = false
        stopRequested = false
        resumeSignal = false
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
            reason: "Typing")
        let t = Thread { [weak self] in self?.runLoop() }
        t.qualityOfService = .userInteractive
        t.name = "Handwritten.typing"
        thread = t
        cond.unlock()
        t.start()
    }

    func requestPause() {
        cond.lock(); pauseRequested = true; cond.broadcast(); cond.unlock()
    }

    func resume() {
        cond.lock(); pauseRequested = false; resumeSignal = true; cond.broadcast(); cond.unlock()
    }

    func stop() {
        cond.lock(); stopRequested = true; cond.broadcast(); cond.unlock()
    }

    func remainingSeconds() -> Double {
        cond.lock(); defer { cond.unlock() }
        guard index < suffix.count else { return 0 }
        return suffix[index]
    }

    /// Run extra steps (used by verification) synchronously on the calling (background) thread.
    func runSteps(_ steps: [Step]) {
        for st in steps {
            cond.lock(); let stop = stopRequested; cond.unlock()
            if stop { return }
            Thread.sleep(forTimeInterval: st.delay)
            sender.perform(st.action, hold: st.hold)
        }
    }

    private static func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

    /// Sleeps until `deadline`, waking often to react to stop/pause. Returns the (possibly
    /// shifted) deadline, or nil if stopped.
    private func sleepUntil(_ deadline: Double, _ i: Int, _ steps: [Step]) -> Double? {
        var deadline = deadline
        while true {
            let left = deadline - Self.now()
            if left <= 0 { return deadline }
            Thread.sleep(forTimeInterval: min(left, 0.015))
            cond.lock()
            let stopNow = stopRequested
            let pauseNow = pauseRequested && canPauseMidStep(i, steps)
            cond.unlock()
            if stopNow { return nil }
            if pauseNow {
                let remaining = max(0, deadline - Self.now())
                if !waitWhilePaused() { return nil }
                deadline = Self.now() + remaining
            }
        }
    }

    private func runLoop() {
        guard let plan = plan else { return }
        let steps = plan.steps
        let total = plan.target.count
        var lastReport = 0.0
        // Delays are measured key-down to key-down; hold time happens inside the next delay.
        var deadline = Self.now()

        while true {
            cond.lock()
            if stopRequested { cond.unlock(); break }
            let i = index
            cond.unlock()
            if i >= steps.count { break }
            let step = steps[i]

            if shouldPauseHere(i, steps) {
                if !waitWhilePaused() { break }
                deadline = Self.now()
            }
            // If we fell behind (e.g. a system hiccup), don't burst to catch up.
            deadline = max(deadline, Self.now() - 0.25) + step.delay
            guard let d = sleepUntil(deadline, i, steps) else { break }
            deadline = d

            sender.perform(step.action, hold: step.hold)

            cond.lock()
            index = i + 1
            let rem = index < suffix.count ? suffix[index] : 0
            cond.unlock()

            let t = Self.now()
            if t - lastReport > 0.05 || i + 1 == steps.count {
                lastReport = t
                let prog = step.progress
                DispatchQueue.main.async { [weak self] in self?.onProgress?(prog, total, rem) }
            }
        }

        cond.lock()
        let wasStopped = stopRequested
        thread = nil
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
        cond.unlock()
        if !wasStopped {
            DispatchQueue.main.async { [weak self] in self?.onFinishedTyping?() }
        }
    }

    private func canPauseMidStep(_ i: Int, _ steps: [Step]) -> Bool {
        guard finishFixBeforePause else { return true }
        return steps[i].group == -1 || (i > 0 && steps[i - 1].group != steps[i].group)
    }

    private func shouldPauseHere(_ i: Int, _ steps: [Step]) -> Bool {
        cond.lock(); defer { cond.unlock() }
        guard pauseRequested else { return false }
        return canPauseMidStep(i, steps)
    }

    /// Blocks until resumed. Returns false if stopped.
    private func waitWhilePaused() -> Bool {
        cond.lock()
        paused = true
        resumeSignal = false
        cond.unlock()
        DispatchQueue.main.async { [weak self] in self?.onPaused?() }
        cond.lock()
        while !resumeSignal && !stopRequested { cond.wait() }
        paused = false
        let ok = !stopRequested
        cond.unlock()
        return ok
    }

    var isStopRequested: Bool { cond.lock(); defer { cond.unlock() }; return stopRequested }
}

// MARK: - Controller

/// Orchestrates countdowns, the engine, the HUD and verification. Main-thread only.
@MainActor
final class TypingController {
    static let shared = TypingController()

    let engine = TypingEngine()
    private let state = AppState.shared
    private var countdownTimer: Timer?
    private var targetPID: pid_t = 0
    private var currentPlan: TypingPlan?
    /// Bumped by every start/stop so a stale planner/countdown can't start typing after Stop.
    private var startToken = 0

    init() {
        engine.onProgress = { [weak self] done, total, rem in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.state.charsDone = done
                self.state.charsTotal = total
                self.state.secondsRemaining = rem
            }
        }
        engine.onPaused = { [weak self] in
            MainActor.assumeIsolated { self?.state.runState = .paused }
        }
        engine.onFinishedTyping = { [weak self] in
            MainActor.assumeIsolated { self?.finishedTyping() }
        }
        let mon = InputMonitor.shared
        mon.onEscape = { [weak self] in
            guard let self, SettingsStore.shared.bool(K.escapeStops), self.state.runState.isActive else { return }
            self.stop(reason: "Stopped (Escape)")
        }
        mon.onUserInterrupt = { [weak self] kind in
            guard let self, self.state.runState == .typing else { return }
            let s = SettingsStore.shared
            if kind == "click" && s.bool(K.autoPauseClick) { self.pause(reason: "Auto-paused (you clicked)") }
            if kind == "key" && s.bool(K.autoPauseKeypress) { self.pause(reason: "Auto-paused (you pressed a key)") }
        }
        mon.onAppSwitch = { [weak self] pid in
            guard let self, self.state.runState == .typing, SettingsStore.shared.bool(K.autoPauseAppSwitch) else { return }
            if pid != self.targetPID && pid != ProcessInfo.processInfo.processIdentifier {
                self.pause(reason: "Auto-paused (app changed)")
            }
        }
    }

    // MARK: Public actions

    func toggleStartPause() {
        switch state.runState {
        case .idle: start()
        case .typing: pause(reason: "Paused")
        case .paused: resume()
        default: break
        }
    }

    func start(text: String? = nil) {
        guard state.runState == .idle else {
            if state.runState == .paused { resume() }
            return
        }
        guard PermissionsManager.shared.accessibility || SettingsStore.shared.bool(K.dryRun) else {
            state.lastMessage = "Accessibility permission is needed to type."
            AppDelegate.shared?.showOnboarding()
            return
        }
        let raw = text ?? ClipboardManager.shared.currentText
        let snap = SettingsStore.shared.snapshot
        let prepared = TextPreparer.prepare(raw, snap)
        guard !prepared.isEmpty else {
            state.lastMessage = "Clipboard is empty."
            NSSound.beep()
            return
        }
        engine.configure(snap)
        let words = WordData.shared.snapshot()
        state.lastMessage = "Planning…"
        // Give focus back to the app the user was in.
        if NSApp.isActive { NSApp.deactivate() }

        let countdown = snap.int(K.countdown)
        startToken += 1
        let token = startToken
        // Mark as starting right away so a 0-second countdown still begins typing.
        state.runState = .countdown(max(0, countdown))
        var plan: TypingPlan?
        let planReady = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            plan = Planner.makePlan(text: prepared, settings: snap, words: words)
            planReady.signal()
        }
        runCountdown(countdown) { [weak self] in
            guard let self else { return }
            // Wait for the planner if it's still working (very long texts).
            DispatchQueue.global().async {
                planReady.wait()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let p = plan, token == self.startToken, self.state.runState != .idle else { return }
                        self.beginTyping(p, snapshot: snap)
                    }
                }
            }
        }
    }

    private func beginTyping(_ p: TypingPlan, snapshot snap: SettingsSnapshot) {
        currentPlan = p
        if snap.bool(K.logPlan) {
            let url = SettingsStore.supportDirNonisolated.appendingPathComponent("last-plan.txt")
            try? p.debugDescription().write(to: url, atomically: true, encoding: .utf8)
        }
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        state.charsDone = 0
        state.charsTotal = p.target.count
        state.plannedDuration = p.totalDuration
        state.secondsRemaining = p.totalDuration
        state.runState = .typing
        state.lastMessage = "Typing…"
        showHUDIfNeeded()
        engine.start(p)
    }

    func pause(reason: String) {
        guard state.runState == .typing || state.runState.isCountdown else { return }
        if state.runState.isCountdown {
            stop(reason: "Cancelled")
            return
        }
        engine.requestPause()
        state.runState = .paused
        state.lastMessage = reason
    }

    func resume() {
        guard state.runState == .paused else { return }
        let s = SettingsStore.shared
        if s.bool(K.warnOnResume) {
            let alert = NSAlert()
            alert.messageText = "Put your cursor back"
            alert.informativeText = "Click back into the text box exactly where typing stopped. Typing resumes after the countdown."
            alert.addButton(withTitle: "Resume")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() != .alertFirstButtonReturn { return }
            NSApp.deactivate()
        } else if NSApp.isActive {
            NSApp.deactivate()
        }
        runCountdown(s.int(K.resumeCountdown)) { [weak self] in
            guard let self else { return }
            self.targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? self.targetPID
            self.state.runState = .typing
            self.state.lastMessage = "Typing…"
            self.engine.resume()
        }
    }

    func stop(reason: String = "Stopped") {
        startToken += 1
        countdownTimer?.invalidate()
        countdownTimer = nil
        engine.stop()
        state.runState = .idle
        state.lastMessage = reason
        hideHUDSoon()
    }

    // MARK: Countdown

    private func runCountdown(_ seconds: Int, then: @escaping () -> Void) {
        countdownTimer?.invalidate()
        guard seconds > 0 else { then(); return }
        var left = seconds
        let wasPaused = state.runState == .paused
        state.runState = .countdown(left)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                guard self.state.runState.isCountdown else { t.invalidate(); return }
                left -= 1
                if left <= 0 {
                    t.invalidate()
                    self.countdownTimer = nil
                    if wasPaused { self.state.runState = .paused }
                    then()
                } else {
                    self.state.runState = .countdown(left)
                }
            }
        }
        RunLoop.main.add(countdownTimer!, forMode: .common)
    }

    // MARK: Finish & verify

    private func finishedTyping() {
        let s = SettingsStore.shared.snapshot
        guard s.bool(K.verifyEnabled), !s.bool(K.dryRun), let plan = currentPlan else {
            complete(message: "Done")
            return
        }
        state.runState = .verifying
        state.lastMessage = "Checking the text…"
        let expected = String(plan.target)
        let engine = self.engine
        let skipVerify = s.bool(K.codeMode) && s.str(K.codeIndentMode) == "strip"
        if skipVerify { complete(message: "Done (check skipped in 'let editor indent' mode)"); return }
        DispatchQueue.global(qos: .userInitiated).async {
            Thread.sleep(forTimeInterval: s.ms(K.verifyDelay))
            let result = Verifier.verifyAndFix(expected: expected, settings: s, engine: engine)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.complete(message: result) }
            }
        }
    }

    private func complete(message: String) {
        state.runState = .idle
        state.charsDone = state.charsTotal
        state.secondsRemaining = 0
        state.lastMessage = message
        hideHUDSoon()
    }

    // MARK: HUD

    private func showHUDIfNeeded() {
        guard SettingsStore.shared.bool(K.showHUD), !state.isMasked else { return }
        WindowManager.shared.showHUD(.hud, size: NSSize(width: 300, height: 74)) { ProgressHUDView().themed() }
    }

    private func hideHUDSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.state.runState == .idle else { return }
                WindowManager.shared.close(.hud)
            }
        }
    }
}

extension RunState {
    var isCountdown: Bool { if case .countdown = self { return true }; return false }
}
