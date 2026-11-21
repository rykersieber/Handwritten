import SwiftUI
import Combine

/// Recomputes the estimated typing time when the clipboard or settings change.
@MainActor
final class EstimateModel: ObservableObject {
    static let shared = EstimateModel()
    @Published private(set) var seconds: Double?
    @Published private(set) var typos = 0
    @Published private(set) var computing = false
    private var cancellables = Set<AnyCancellable>()
    private var work: DispatchWorkItem?
    private var generation = 0

    init() {
        ClipboardManager.shared.$currentText.removeDuplicates().sink { [weak self] _ in self?.schedule() }.store(in: &cancellables)
        SettingsStore.didChange.sink { [weak self] _ in self?.schedule() }.store(in: &cancellables)
    }

    func schedule() {
        work?.cancel()
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.compute() } }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    private func compute() {
        let snap = SettingsStore.shared.snapshot
        let text = TextPreparer.prepare(ClipboardManager.shared.currentText, snap)
        guard !text.isEmpty else { seconds = nil; return }
        generation += 1
        let gen = generation
        computing = true
        let words = WordData.shared.snapshot()
        DispatchQueue.global(qos: .utility).async {
            let plan = Planner.makePlan(text: text, settings: snap, words: words)
            let secs = plan.totalDuration, typos = plan.typoCount
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard gen == self.generation else { return }
                    self.seconds = secs
                    self.typos = typos
                    self.computing = false
                }
            }
        }
    }
}

struct ControlPanelView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var clip = ClipboardManager.shared
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var presets = PresetStore.shared
    @ObservedObject private var estimate = EstimateModel.shared
    @ObservedObject private var perms = PermissionsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader
            if !perms.allGranted { permissionBanner }
            controls
            previewBox
            quickSettings
            historyList
            footer
        }
        .padding(16)
        .frame(minWidth: 360, idealWidth: 400, minHeight: 560)
    }

    // MARK: Sections

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(statusColor).frame(width: 10, height: 10)
                Text(statusText).font(.headline)
                Spacer()
                if state.runState.isActive {
                    Text(state.percentText).font(.headline.monospacedDigit())
                }
            }
            if state.runState.isActive {
                ColoredProgressBar(value: state.fraction, color: statusColor)
                HStack {
                    Text("\(state.charsDone) / \(state.charsTotal) characters")
                    Spacer()
                    Text("\(TimeFormat.short(state.secondsRemaining)) left")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            if !state.lastMessage.isEmpty && !state.runState.isActive {
                Text(state.lastMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var permissionBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Permissions needed before typing works.").font(.callout)
            Spacer()
            Button("Fix…") { AppDelegate.shared?.showOnboarding() }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    private var controls: some View {
        HStack(spacing: 8) {
            let rs = state.runState
            Button {
                if rs == .paused { TypingController.shared.resume() } else { TypingController.shared.start() }
            } label: {
                Label(rs == .paused ? "Resume" : "Start", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!(rs == .idle || rs == .paused))
            .keyboardShortcut(.defaultAction)

            Button { TypingController.shared.pause(reason: "Paused") } label: {
                Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity)
            }
            .disabled(rs != .typing && !rs.isCountdown)

            Button(role: .destructive) { TypingController.shared.stop() } label: {
                Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .disabled(!rs.isActive)
        }
        .controlSize(.large)
    }

    private var previewBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("About to type").font(.subheadline.bold())
                Spacer()
                Text("\(clip.currentText.count) chars · \(clip.currentText.split { $0.isWhitespace }.count) words")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                Text(previewText)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .foregroundStyle(clip.currentText.isEmpty ? .secondary : .primary)
            }
            .frame(height: 90)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            HStack {
                Image(systemName: "clock")
                if let secs = estimate.seconds {
                    Text("Takes about \(TimeFormat.short(secs))")
                    if estimate.typos > 0 { Text("· ~\(estimate.typos) typos").foregroundStyle(.secondary) }
                } else {
                    Text(clip.currentText.isEmpty ? "Copy some text to get started" : "Estimating…")
                }
                Spacer()
                if let current = clip.items.first(where: { $0.text == clip.currentText }) {
                    Button("Edit") { AppDelegate.shared?.showHistoryEditor(current) }.controlSize(.small)
                }
            }
            .font(.caption)
            if store.bool(K.typosEnabled) && SystemText.protectionActive(store.snapshot) && !store.bool(K.safeTypoMode) {
                Label("Your Mac's autocorrect is on, so typos are always fixed before the word ends.",
                      systemImage: "checkmark.shield")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("Change this in Settings → Typos → Autocorrect protection.")
            }
            if store.str(K.typingInto) == "word" && store.bool(K.autocorrectReminder) {
                Label("Tip: turn off AutoCorrect in Word (Preferences → AutoCorrect), or turn on Safe typo mode.",
                      systemImage: "lightbulb")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var previewText: String {
        let t = clip.currentText
        if t.isEmpty { return "Clipboard is empty." }
        let n = store.int(K.previewLength)
        return t.count > n ? String(t.prefix(n)) + "…" : t
    }

    private var quickSettings: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Preset", selection: Binding(
                    get: { presets.preset(named: store.activePresetName) == nil ? Preset.customName : store.activePresetName },
                    set: { name in
                        if name == Preset.customName { store.useCustom() }
                        else if let p = presets.preset(named: name) { store.apply(preset: p) }
                    })) {
                    Text("Custom (my settings)").tag(Preset.customName)
                    Divider()
                    ForEach(presets.all) { p in Text(p.name).tag(p.name) }
                }
                .help("Pick a preset, or Custom to use your own settings. Changing any typing setting switches to Custom.")
                Picker("Into", selection: Binding(
                    get: { store.str(K.typingInto) },
                    set: { TypingProfiles.apply($0) })) {
                    Text("General").tag("general")
                    Text("Browser").tag("browser")
                    Text("Word").tag("word")
                    Text("Code").tag("code")
                }
                .frame(width: 140)
            }
            HStack {
                Picker("", selection: Binding(get: { store.str(K.speedMode) }, set: { store.set(K.speedMode, $0) })) {
                    Text("WPM").tag("wpm")
                    Text("Timer").tag("timer")
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                if store.str(K.speedMode) == "timer" {
                    QuickNumber(key: K.timerMinutes, label: "min")
                } else {
                    QuickNumber(key: K.wpm, label: "WPM")
                }
            }
            HStack {
                Text("Humanness").font(.callout)
                QuickNumber(key: K.humanness, label: "%")
            }
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("History").font(.subheadline.bold())
                Spacer()
                Text("Click to use · doesn't start typing").font(.caption2).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 4) {
                    if clip.items.isEmpty {
                        Text("Nothing copied yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding()
                    }
                    ForEach(clip.items) { item in HistoryRow(item: item, isCurrent: item.text == clip.currentText) }
                }
            }
            .frame(minHeight: 100)
        }
    }

    private var footer: some View {
        HStack {
            Button { AppDelegate.shared?.showSettings() } label: { Label("Settings", systemImage: "gearshape") }
            Spacer()
            Button { AppDelegate.shared?.showPersonalize() } label: { Label("Personalize", systemImage: "person.crop.circle.badge.checkmark") }
                .help("Type a sample paragraph and Handwritten learns to type like you.")
            Spacer()
            Button { AppDelegate.shared?.setMasked(true) } label: { Label("Mask", systemImage: "eye.slash") }
                .help("Hide everything. Use the mask hotkey to bring it back.")
        }
    }

    private var statusColor: Color {
        switch state.runState {
        case .idle: return .gray
        case .countdown: return .orange
        case .typing, .verifying: return ThemeStore.shared.accent
        case .paused: return .yellow
        }
    }

    private var statusText: String {
        switch state.runState {
        case .idle: return "Ready"
        case .countdown(let n): return "Starting in \(n)… click into your text box"
        case .typing: return "Typing"
        case .paused: return "Paused"
        case .verifying: return "Checking the text…"
        }
    }
}

private struct HistoryRow: View {
    let item: ClipboardItem
    let isCurrent: Bool
    @ObservedObject private var store = SettingsStore.shared
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isCurrent ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isCurrent ? ThemeStore.shared.accent : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview(140)).font(.callout).lineLimit(2)
                Text("\(item.text.count) chars\(item.sourceApp.map { " · from \($0)" } ?? "") · \(item.date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if store.bool(K.pinsEnabled) {
                Button { ClipboardManager.shared.togglePin(item) } label: {
                    Image(systemName: item.pinned ? "pin.fill" : "pin")
                }.buttonStyle(.borderless).help(item.pinned ? "Unpin" : "Pin")
            }
            Button { AppDelegate.shared?.showHistoryEditor(item) } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless).help("Edit before typing")
            Button { ClipboardManager.shared.delete(item) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("Remove from history")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(isCurrent ? ThemeStore.shared.accent.opacity(0.12) : Color.primary.opacity(hover ? 0.07 : 0.03)))
        .contentShape(Rectangle())
        .onTapGesture { ClipboardManager.shared.select(item) }
        .onHover { hover = $0 }
    }
}

/// Compact slider + number field bound to a numeric setting.
struct QuickNumber: View {
    let key: String
    let label: String
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        if let d = SettingsRegistry.def(key), case .number(let mn, let mx, let step, _) = d.kind {
            let upper = key == K.timerMinutes ? min(mx, 180) : (key == K.wpm ? min(mx, 200) : mx)
            HStack {
                Slider(value: Binding(get: { min(upper, store.num(key)) }, set: { store.set(key, ($0 / step).rounded() * step) }),
                       in: mn...upper)
                TextField("", value: Binding(get: { store.num(key) }, set: { store.set(key, min(mx, max(mn, $0))) }),
                          format: .number.precision(.fractionLength(0...1)))
                    .frame(width: 56)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
            }
        }
    }
}

/// "Typing into" quick profiles.
enum TypingProfiles {
    @MainActor static func apply(_ profile: String) {
        let s = SettingsStore.shared
        let preset = s.activePresetName
        defer { s.activePresetName = preset }
        s.set(K.typingInto, profile)
        switch profile {
        case "browser":
            s.set(K.newlineMode, "shiftReturn"); s.set(K.codeMode, false); s.set(K.tabMode, "spaces")
        case "word":
            s.set(K.newlineMode, "return"); s.set(K.codeMode, false); s.set(K.safeTypoMode, true); s.set(K.tabMode, "tab")
        case "code":
            s.set(K.newlineMode, "return"); s.set(K.codeMode, true); s.set(K.tabMode, "tab")
        default:
            s.set(K.newlineMode, "shiftReturn"); s.set(K.codeMode, false)
        }
    }
}
