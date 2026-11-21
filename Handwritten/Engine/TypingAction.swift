import Foundation

/// One thing the engine does to the keyboard.
enum KeyAction: Equatable {
    case char(Character)
    case newline
    case tab
    case backspace
    case optionBackspace
    case left
    case right
    case cmdRight
    case forwardDelete
    /// Code mode: type a placeholder then ⌘⇧← to select the editor's auto-indent.
    case codeIndentSelect
    /// Backspace that only deletes a selection (doesn't change our text model).
    case deleteSelection
    /// No key, just time passing.
    case wait

    var describe: String {
        switch self {
        case .char(let c):
            switch c {
            case " ": return "␣"
            default: return String(c)
            }
        case .newline: return "⏎"
        case .tab: return "⇥"
        case .backspace: return "⌫"
        case .optionBackspace: return "⌥⌫"
        case .left: return "←"
        case .right: return "→"
        case .cmdRight: return "⌘→"
        case .forwardDelete: return "⌦"
        case .codeIndentSelect: return "[indent-select]"
        case .deleteSelection: return "[del-sel]"
        case .wait: return "[wait]"
        }
    }
}

struct Step {
    var action: KeyAction
    /// Time between the previous key press and this one from typing speed.
    var keyDelay: Double
    /// Extra time from pauses (punctuation, thinking, breaks…).
    var pauseDelay: Double
    /// How long the key is held down (fits inside the next interval).
    var hold: Double
    /// Steps that belong to one typo + its fix share a group id (−1 = none).
    var group: Int
    /// Target characters correctly typed after this step.
    var progress: Int

    var delay: Double { keyDelay + pauseDelay }
}

struct TypingPlan {
    var steps: [Step]
    var target: [Character]
    /// What our model says the text box contains at the end.
    var finalModel: [Character]
    var unfixedLeft: Int
    var typoCount: Int

    var totalDuration: Double { steps.reduce(0) { $0 + $1.delay } }

    /// remaining[i] = total delay of steps i..<end.
    func suffixDurations() -> [Double] {
        var out = [Double](repeating: 0, count: steps.count + 1)
        var acc = 0.0
        for i in stride(from: steps.count - 1, through: 0, by: -1) {
            acc += steps[i].delay
            out[i] = acc
        }
        return out
    }

    func debugDescription() -> String {
        var s = "Handwritten plan — \(steps.count) steps, \(String(format: "%.1f", totalDuration))s, typos \(typoCount), unfixed left \(unfixedLeft)\n"
        for (i, st) in steps.enumerated() {
            s += String(format: "%6d  +%.3f  (key %.3f, pause %.3f)  g%-4d p%-6d %@\n",
                        i, st.delay, st.keyDelay, st.pauseDelay, st.group, st.progress, st.action.describe)
        }
        return s
    }
}
