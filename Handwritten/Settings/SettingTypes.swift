import Foundation

/// How much of the settings UI a user sees.
enum SettingLevel: Int, Codable, CaseIterable, Comparable, Identifiable {
    case simple = 0, advanced = 1, custom = 2
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .simple: return "Simple"
        case .advanced: return "Advanced"
        case .custom: return "Custom"
        }
    }
    static func < (a: SettingLevel, b: SettingLevel) -> Bool { a.rawValue < b.rawValue }
}

enum SettingTab: String, CaseIterable, Identifiable {
    case general, speed, rhythm, typos, corrections, text, clipboard, hotkeys, mask, appearance, presets, wordLists, developer
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .speed: return "Speed"
        case .rhythm: return "Rhythm & Pauses"
        case .typos: return "Typos"
        case .corrections: return "Corrections"
        case .text: return "Text Handling"
        case .clipboard: return "Clipboard"
        case .hotkeys: return "Hotkeys"
        case .mask: return "Mask"
        case .appearance: return "Appearance"
        case .presets: return "Presets"
        case .wordLists: return "Word Lists"
        case .developer: return "Developer"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .speed: return "speedometer"
        case .rhythm: return "waveform.path"
        case .typos: return "character.cursor.ibeam"
        case .corrections: return "delete.left"
        case .text: return "text.alignleft"
        case .clipboard: return "doc.on.clipboard"
        case .hotkeys: return "command"
        case .mask: return "eye.slash"
        case .appearance: return "paintpalette"
        case .presets: return "square.stack.3d.up"
        case .wordLists: return "list.bullet.rectangle"
        case .developer: return "hammer"
        }
    }

    /// Minimum UI level at which the tab itself appears.
    var minLevel: SettingLevel { self == .developer ? .custom : .simple }
}

enum SettingValue: Codable, Equatable, Hashable {
    case number(Double)
    case bool(Bool)
    case text(String)

    var number: Double? { if case .number(let v) = self { return v }; return nil }
    var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    var text: String? { if case .text(let v) = self { return v }; return nil }

    private enum CodingKeys: String, CodingKey { case n, b, s }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(Double.self, forKey: .n) { self = .number(v); return }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .b) { self = .bool(v); return }
        self = .text(try c.decodeIfPresent(String.self, forKey: .s) ?? "")
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .number(let v): try c.encode(v, forKey: .n)
        case .bool(let v): try c.encode(v, forKey: .b)
        case .text(let v): try c.encode(v, forKey: .s)
        }
    }
}

struct ChoiceOption: Hashable {
    let value: String
    let label: String
}

enum SettingKind {
    /// Numeric with slider + number field.
    case number(min: Double, max: Double, step: Double, unit: String)
    case toggle
    case choice([ChoiceOption])
    case text(placeholder: String)
    case hotkey
    case color
}

/// Describes one setting for the UI, search, defaults, and the humanness curve.
struct SettingDef: Identifiable {
    let key: String
    let title: String
    let help: String
    let tab: SettingTab
    let section: String
    let level: SettingLevel
    let kind: SettingKind
    let defaultValue: SettingValue
    /// If set, the humanness slider drives this numeric value from `.0` (0% human) to `.1` (100% human).
    /// Values in between follow a smooth curve around the default at 50%.
    let human: (Double, Double)?
    /// Optional key whose bool must be true for this row to be enabled.
    let dependsOn: String?

    var id: String { key }

    var searchText: String {
        "\(title) \(help) \(section) \(tab.title) \(key)".lowercased()
    }
}
