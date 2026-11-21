import Foundation
import Carbon.HIToolbox

/// US QWERTY layout: character → key code / shift, plus finger, row and position
/// (used for timing and realistic neighbor-key typos).
struct KeyInfo {
    let keyCode: UInt16
    let shift: Bool
    let base: Character   // unshifted character on that key
    let row: Int          // 0 number, 1 top, 2 home, 3 bottom, 4 space
    let x: Double         // horizontal position in key widths
    let finger: Int       // 0...7 left pinky → right pinky, 8 thumbs
    var hand: Int { finger == 8 ? 2 : (finger < 4 ? 0 : 1) }
}

enum KeyLayout {
    // (unshifted, shifted, keyCode) per row, left to right.
    private static let rows: [(start: Double, keys: [(Character, Character, Int)])] = [
        (0.0, [("`", "~", kVK_ANSI_Grave), ("1", "!", kVK_ANSI_1), ("2", "@", kVK_ANSI_2), ("3", "#", kVK_ANSI_3),
               ("4", "$", kVK_ANSI_4), ("5", "%", kVK_ANSI_5), ("6", "^", kVK_ANSI_6), ("7", "&", kVK_ANSI_7),
               ("8", "*", kVK_ANSI_8), ("9", "(", kVK_ANSI_9), ("0", ")", kVK_ANSI_0), ("-", "_", kVK_ANSI_Minus),
               ("=", "+", kVK_ANSI_Equal)]),
        (1.5, [("q", "Q", kVK_ANSI_Q), ("w", "W", kVK_ANSI_W), ("e", "E", kVK_ANSI_E), ("r", "R", kVK_ANSI_R),
               ("t", "T", kVK_ANSI_T), ("y", "Y", kVK_ANSI_Y), ("u", "U", kVK_ANSI_U), ("i", "I", kVK_ANSI_I),
               ("o", "O", kVK_ANSI_O), ("p", "P", kVK_ANSI_P), ("[", "{", kVK_ANSI_LeftBracket),
               ("]", "}", kVK_ANSI_RightBracket), ("\\", "|", kVK_ANSI_Backslash)]),
        (1.75, [("a", "A", kVK_ANSI_A), ("s", "S", kVK_ANSI_S), ("d", "D", kVK_ANSI_D), ("f", "F", kVK_ANSI_F),
                ("g", "G", kVK_ANSI_G), ("h", "H", kVK_ANSI_H), ("j", "J", kVK_ANSI_J), ("k", "K", kVK_ANSI_K),
                ("l", "L", kVK_ANSI_L), (";", ":", kVK_ANSI_Semicolon), ("'", "\"", kVK_ANSI_Quote)]),
        (2.25, [("z", "Z", kVK_ANSI_Z), ("x", "X", kVK_ANSI_X), ("c", "C", kVK_ANSI_C), ("v", "V", kVK_ANSI_V),
                ("b", "B", kVK_ANSI_B), ("n", "N", kVK_ANSI_N), ("m", "M", kVK_ANSI_M), (",", "<", kVK_ANSI_Comma),
                (".", ">", kVK_ANSI_Period), ("/", "?", kVK_ANSI_Slash)]),
    ]

    // Finger by (row, index) for standard touch typing.
    private static let fingers: [[Int]] = [
        [0, 0, 1, 2, 3, 3, 4, 4, 5, 6, 7, 7, 7],
        [0, 1, 2, 3, 3, 4, 4, 5, 6, 7, 7, 7, 7],
        [0, 1, 2, 3, 3, 4, 4, 5, 6, 7, 7],
        [0, 1, 2, 3, 3, 4, 4, 5, 6, 7],
    ]

    static let table: [Character: KeyInfo] = {
        var t: [Character: KeyInfo] = [:]
        for (r, row) in rows.enumerated() {
            for (i, k) in row.keys.enumerated() {
                let x = row.start + Double(i)
                let f = fingers[r][i]
                t[k.0] = KeyInfo(keyCode: UInt16(k.2), shift: false, base: k.0, row: r, x: x, finger: f)
                t[k.1] = KeyInfo(keyCode: UInt16(k.2), shift: true, base: k.0, row: r, x: x, finger: f)
            }
        }
        t[" "] = KeyInfo(keyCode: UInt16(kVK_Space), shift: false, base: " ", row: 4, x: 6, finger: 8)
        return t
    }()

    private static let byKeyCode: [UInt16: Character] = {
        var m: [UInt16: Character] = [:]
        for (c, info) in table where !info.shift { m[info.keyCode] = c }
        return m
    }()

    static func info(_ c: Character) -> KeyInfo? { table[c] }
    static func character(forKeyCode code: UInt16) -> Character? { byKeyCode[code] }

    /// Neighboring characters (same shift state), split into direct (same row) and diagonal.
    static func neighbors(of c: Character) -> (direct: [Character], diagonal: [Character]) {
        guard let me = table[c], me.row < 4 else { return ([], []) }
        var direct: [Character] = [], diag: [Character] = []
        for (r, row) in rows.enumerated() where abs(r - me.row) <= 1 {
            for (i, k) in row.keys.enumerated() {
                let x = row.start + Double(i)
                let ch = me.shift ? k.1 : k.0
                if ch == c { continue }
                let dx = abs(x - me.x)
                if r == me.row && dx <= 1.01 { direct.append(ch) }
                else if r != me.row && dx <= 0.8 { diag.append(ch) }
            }
        }
        return (direct, diag)
    }

    private static let mirrorPairs: [(Character, Character)] = [
        ("q", "p"), ("w", "o"), ("e", "i"), ("r", "u"), ("t", "y"),
        ("a", ";"), ("s", "l"), ("d", "k"), ("f", "j"), ("g", "h"),
        ("z", "/"), ("x", "."), ("c", ","), ("v", "m"), ("b", "n"),
    ]
    private static let mirrorMap: [Character: Character] = {
        var m: [Character: Character] = [:]
        for (a, b) in mirrorPairs { m[a] = b; m[b] = a }
        return m
    }()

    /// The same key on the other hand (letters only).
    static func mirror(of c: Character) -> Character? {
        let lower = Character(c.lowercased())
        guard let m = mirrorMap[lower], m.isLetter else { return nil }
        return c.isUppercase ? Character(m.uppercased()) : m
    }
}
