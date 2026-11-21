import Foundation
import Combine

enum RunState: Equatable {
    case idle
    case countdown(Int)
    case typing
    case paused
    case verifying

    var isActive: Bool { self != .idle }
    var isRunningOrCounting: Bool {
        switch self {
        case .typing, .verifying, .countdown: return true
        default: return false
        }
    }
}

/// Global, observable UI state. Everything here is read on the main thread.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var runState: RunState = .idle
    @Published var charsDone: Int = 0
    @Published var charsTotal: Int = 0
    @Published var secondsRemaining: Double = 0
    @Published var plannedDuration: Double = 0
    @Published var isMasked: Bool = false
    @Published var lastMessage: String = ""

    var fraction: Double {
        charsTotal == 0 ? 0 : min(1, Double(charsDone) / Double(charsTotal))
    }

    var percentText: String { "\(Int((fraction * 100).rounded()))%" }
}

enum TimeFormat {
    static func short(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }
}
