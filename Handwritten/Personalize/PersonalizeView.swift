import SwiftUI
import AppKit

// MARK: - Model

@MainActor
final class PersonalizeModel: ObservableObject {
    enum Phase { case intro, typing, analyzing, results }

    static let samples: [(title: String, text: String)] = [
        ("Everyday", "The best way to learn something new is to practice it a little every day. Last week I spent about 20 minutes each morning reading, and by Friday I had finished 3 chapters! It wasn't always easy, but it was worth it. Next, I'm planning to try writing short stories; maybe I'll share one with you soon."),
        ("School essay", "Throughout history, people have relied on stories to explain the world around them. In many ancient cultures, myths described why the seasons changed and where the stars came from. Today, we use science to answer those same questions, yet stories still matter. They help us remember facts, share values, and connect with each other."),
        ("Casual message", "Hey! Are you still free on Saturday? I was thinking we could grab lunch around 12:30 and then check out that new store downtown. Let me know what works for you, and if Sam wants to come too, that's totally fine. Can't wait to catch up!"),
        ("Work email", "Hi Jordan, thanks for sending over the report. I reviewed the numbers from Q3 and everything looks good, although I had a quick question about the budget on page 4. Could we set up a 15-minute call on Tuesday or Wednesday to go over it? Best regards, Alex"),
    ]

    @Published var phase: Phase = .intro
    @Published var sampleIndex = 0
    @Published var useClipboard = false
    @Published var typed = ""
    @Published var keys: [RecordedKey] = []
    @Published var analysis: TypingAnalysis?
    @Published var applied = false
    @Published var presetName = "My Typing"
    private var downIndex: [UInt16: Int] = [:]

    var sample: String {
        if useClipboard {
            let t = ClipboardManager.shared.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count >= 80 { return String(t.prefix(1200)) }
        }
        return Self.samples[sampleIndex].text
    }

    var elapsed: Double {
        guard let f = keys.first, let l = keys.last else { return 0 }
        return l.time - f.time
    }

    var liveWPM: Double {
        guard elapsed > 2 else { return 0 }
        return Double(typed.count) / 5.0 / (elapsed / 60)
    }

    var progress: Double { min(1, Double(typed.count) / Double(max(1, sample.count))) }

    func start() {
        typed = ""; keys = []; downIndex = [:]; analysis = nil; applied = false
        phase = .typing
    }

    func record(_ key: RecordedKey, keyCode: UInt16) {
        keys.append(key)
        downIndex[keyCode] = keys.count - 1
    }

    func recordUp(keyCode: UInt16, time: Double) {
        guard let i = downIndex[keyCode], i < keys.count, keys[i].hold == nil else { return }
        keys[i].hold = time - keys[i].time
        downIndex[keyCode] = nil
    }

    func finish() {
        phase = .analyzing
        let k = keys, s = sample, f = typed
        let base = SettingsStore.shared.snapshot
        let words = WordData.shared.snapshot()
        DispatchQueue.global(qos: .userInitiated).async {
            let a = TypingAnalyzer.analyze(keys: k, sample: s, finalText: f, base: base, words: words)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.analysis = a
                    self.phase = .results
                }
            }
        }
    }

    func apply() {
        guard let a = analysis, !a.values.isEmpty else { return }
        var name = presetName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty || PresetStore.shared.isReserved(name) { name = "My Typing" }
        let df = DateFormatter(); df.dateStyle = .medium
        let p = Preset(name: name, detail: "Learned from your typing on \(df.string(from: Date())) · \(Int(a.wpm)) WPM",
                       values: a.values)
        PresetStore.shared.save(p)
        if let saved = PresetStore.shared.preset(named: name) { SettingsStore.shared.apply(preset: saved) }
        applied = true
    }
}

// MARK: - View

struct PersonalizeView: View {
    @StateObject private var model: PersonalizeModel
    @MainActor init(model: PersonalizeModel? = nil) { _model = StateObject(wrappedValue: model ?? PersonalizeModel()) }
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            switch model.phase {
            case .intro: intro
            case .typing: typing
            case .analyzing:
                VStack { ProgressView(); Text("Analyzing your typing…").foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .results: results
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 28)).foregroundStyle(ThemeStore.shared.accent)
            VStack(alignment: .leading) {
                Text("Personalize").font(.title2.bold())
                Text("Type a paragraph the way you normally would. Handwritten learns your speed, pauses and typos, and copies them.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Sample text", selection: $model.sampleIndex) {
                ForEach(PersonalizeModel.samples.indices, id: \.self) { Text(PersonalizeModel.samples[$0].title).tag($0) }
            }
            .frame(width: 320)
            .disabled(model.useClipboard)
            Toggle("Use my clipboard text instead (at least 80 characters)", isOn: $model.useClipboard)
            Text(model.sample)
                .font(.system(.body, design: .serif))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            VStack(alignment: .leading, spacing: 4) {
                Label("Type normally. Don't try to be perfect; your real typos and fixes are what it learns from.", systemImage: "hand.wave")
                Label("Autocorrect is turned off in the typing box so your real mistakes count.", systemImage: "textformat.abc")
                Label("Nothing you type is saved or sent anywhere. Only the timing settings are kept.", systemImage: "lock")
            }
            .font(.callout).foregroundStyle(.secondary)
            Spacer()
            HStack {
                Spacer()
                Button("Start Typing") { model.start() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Typing

    private var typing: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Type this:").font(.subheadline.bold())
            ScrollView {
                coloredSample
                    .font(.system(.body, design: .serif))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 120)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))

            RecorderTextView(model: model)
                .frame(minHeight: 150)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ThemeStore.shared.accent.opacity(0.5)))

            ColoredProgressBar(value: model.progress, color: ThemeStore.shared.accent)
            HStack {
                Text("\(model.typed.count) / \(model.sample.count) characters")
                Text("·")
                Text(model.liveWPM > 0 ? "\(Int(model.liveWPM)) WPM" : "— WPM")
                Text("·")
                Text("\(model.keys.filter { $0.kind == .backspace || $0.kind == .optionBackspace }.count) backspaces")
                Spacer()
                Button("Start Over") { model.start() }
                Button("Finish & Analyze") { model.finish() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.typed.count < 60)
                    .help("Type at least 60 characters. The whole paragraph gives the best results.")
            }
            .font(.callout.monospacedDigit())
        }
    }

    /// The sample with what you've typed so far marked green (right) / red (wrong).
    private var coloredSample: Text {
        let s = Array(model.sample), t = Array(model.typed)
        var out = Text("")
        for (i, c) in s.enumerated() {
            let piece = Text(String(c))
            if i < t.count {
                out = out + piece.foregroundColor(t[i] == c ? .green : .red)
            } else if i == t.count {
                out = out + piece.underline().foregroundColor(.primary)
            } else {
                out = out + piece.foregroundColor(.secondary)
            }
        }
        return out
    }

    // MARK: Results

    private var results: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let a = model.analysis {
                HStack(spacing: 24) {
                    stat("\(Int(a.wpm))", "WPM")
                    stat("\(Int((a.accuracy * 100).rounded()))%", "accuracy")
                    stat("\(a.corrections)", "corrections")
                    stat(TimeFormat.short(a.duration), "time")
                }
                ForEach(a.warnings, id: \.self) { w in
                    Label(w, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                }
                if a.rows.isEmpty {
                    Text("Couldn't learn anything from that. Try typing the whole paragraph.").foregroundStyle(.secondary)
                } else {
                    Table(a.rows) {
                        TableColumn("Setting") { r in
                            VStack(alignment: .leading) {
                                Text(r.title)
                                if !r.note.isEmpty { Text(r.note).font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                        TableColumn("You") { r in Text(format(r.value, r.unit)).bold().foregroundStyle(ThemeStore.shared.accent) }
                            .width(110)
                        TableColumn("Current") { r in Text(format(store.num(r.key), r.unit)).foregroundStyle(.secondary) }
                            .width(110)
                    }
                    .frame(minHeight: 240)
                }
                HStack {
                    Button("Type Again") { model.start() }
                    Spacer()
                    if model.applied {
                        Label("Saved and loaded “\(model.presetName)”", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    TextField("Preset name", text: $model.presetName).textFieldStyle(.roundedBorder).frame(width: 160)
                    Button("Use These Settings") { model.apply() }
                        .buttonStyle(.borderedProminent)
                        .disabled(a.rows.isEmpty)
                        .help("Saves a preset with your typing style and loads it. Settings it couldn't measure keep their defaults.")
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading) {
            Text(value).font(.title.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func format(_ v: Double, _ unit: String) -> String {
        let num = v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
        return unit.isEmpty ? num : "\(num) \(unit)"
    }
}

// MARK: - Recorder

/// A text box that records the exact time of every key press and release.
struct RecorderTextView: NSViewRepresentable {
    @ObservedObject var model: PersonalizeModel

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = RecordingTextView.scrollableTextView()
        scroll.drawsBackground = false
        let old = scroll.documentView as! NSTextView
        let tv = RecordingTextView(frame: old.frame, textContainer: old.textContainer)
        tv.autoresizingMask = old.autoresizingMask
        tv.isRichText = false
        tv.drawsBackground = false
        tv.font = .systemFont(ofSize: 15)
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticTextCompletionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        if #available(macOS 14.0, *) { tv.inlinePredictionType = .no }
        tv.insertionPointColor = ThemeStore.shared.nsAccent
        tv.delegate = context.coordinator
        tv.onKeyDown = { key, code in model.record(key, keyCode: code) }
        tv.onKeyUp = { code, time in model.recordUp(keyCode: code, time: time) }
        scroll.documentView = tv
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let tv = nsView.documentView as? NSTextView, model.typed.isEmpty, !tv.string.isEmpty {
            tv.string = "" // Start Over
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: PersonalizeModel
        init(model: PersonalizeModel) { self.model = model }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let s = tv.string
            MainActor.assumeIsolated { model.typed = s }
        }
    }
}

final class RecordingTextView: NSTextView {
    var onKeyDown: ((RecordedKey, UInt16) -> Void)?
    var onKeyUp: ((UInt16, Double) -> Void)?

    override func keyDown(with e: NSEvent) {
        let kind: RecordedKey.Kind
        switch e.keyCode {
        case 51: kind = e.modifierFlags.contains(.option) ? .optionBackspace : .backspace
        case 123: kind = .left
        case 124: kind = .right
        case 36, 76: kind = .char("\n")
        case 48: kind = .char("\t")
        default:
            if !e.modifierFlags.contains(.command), let c = e.characters?.first, !c.isASCII || !c.unicodeScalars.allSatisfy({ $0.value < 32 }) {
                kind = .char(c)
            } else {
                kind = .other
            }
        }
        onKeyDown?(RecordedKey(time: e.timestamp, kind: kind, hold: nil, isRepeat: e.isARepeat), e.keyCode)
        super.keyDown(with: e)
    }

    override func keyUp(with e: NSEvent) {
        onKeyUp?(e.keyCode, e.timestamp)
        super.keyUp(with: e)
    }

    // Pasting would skip the typing we're trying to measure.
    override func paste(_ sender: Any?) { NSSound.beep() }
}
