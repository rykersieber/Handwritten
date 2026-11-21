import SwiftUI

/// Small floating, movable progress window. Never takes keyboard focus.
struct ProgressHUDView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        let scale = store.num(K.hudScale) / 100
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(state.percentText).font(.system(size: 12, weight: .semibold).monospacedDigit())
                Button { TypingController.shared.toggleStartPause() } label: {
                    Image(systemName: state.runState == .paused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.borderless)
                .disabled(!(state.runState == .typing || state.runState == .paused))
                Button { TypingController.shared.stop() } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(.borderless)
                    .disabled(!state.runState.isActive)
            }
            ColoredProgressBar(value: state.fraction, color: color)
            HStack {
                Text("\(state.charsDone) / \(state.charsTotal)")
                Spacer()
                if store.bool(K.hudShowsETA) { Text("\(TimeFormat.short(state.secondsRemaining)) left") }
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(width: 280)
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1)))
        .opacity(store.num(K.hudOpacity) / 100)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: 280 * scale + 20, height: 74 * scale + 10, alignment: .topLeading)
        .padding(.leading, 0)
    }

    private var title: String {
        switch state.runState {
        case .countdown(let n): return "Starting in \(n)…"
        case .typing: return "Typing"
        case .paused: return "Paused"
        case .verifying: return "Checking…"
        case .idle: return state.lastMessage.isEmpty ? "Done" : state.lastMessage
        }
    }

    private var icon: String {
        switch state.runState {
        case .paused: return "pause.circle.fill"
        case .idle: return "checkmark.circle.fill"
        case .countdown: return "timer"
        default: return "pencil.line"
        }
    }

    private var color: Color {
        switch state.runState {
        case .paused: return .yellow
        case .countdown: return .orange
        case .idle: return .green
        default: return ThemeStore.shared.accent
        }
    }
}

/// Progress bar that always uses the given color (system ProgressView ignores tint in some windows).
struct ColoredProgressBar: View {
    let value: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(color).frame(width: max(height, geo.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.15), value: value)
    }
}
