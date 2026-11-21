import AppKit
import SwiftUI
import Combine

@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published private(set) var accent: Color = .blue
    @Published private(set) var nsAccent: NSColor = .systemBlue
    @Published private(set) var scheme: ColorScheme? = nil

    private var cancellable: AnyCancellable?

    init() {
        apply()
        cancellable = SettingsStore.didChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] key in
                if key == "*" || key.hasPrefix("app.") { self?.apply() }
            }
    }

    func apply() {
        let s = SettingsStore.shared
        let ns: NSColor
        switch s.str(K.accent) {
        case "purple": ns = .systemPurple
        case "pink": ns = .systemPink
        case "red": ns = .systemRed
        case "orange": ns = .systemOrange
        case "yellow": ns = .systemYellow
        case "green": ns = .systemGreen
        case "graphite": ns = .systemGray
        case "custom": ns = NSColor(hex: s.str(K.customAccent)) ?? .systemBlue
        default: ns = .systemBlue
        }
        nsAccent = ns
        accent = Color(nsColor: ns)
        switch s.str(K.theme) {
        case "light": scheme = .light; NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": scheme = .dark; NSApp.appearance = NSAppearance(named: .darkAqua)
        default: scheme = nil; NSApp.appearance = nil
        }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#5B8CFF" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

/// Applies the user's accent + theme to any SwiftUI view.
struct Themed: ViewModifier {
    @ObservedObject var theme = ThemeStore.shared
    func body(content: Content) -> some View {
        content.tint(theme.accent).accentColor(theme.accent).preferredColorScheme(theme.scheme)
    }
}

extension View {
    func themed() -> some View { modifier(Themed()) }
}
