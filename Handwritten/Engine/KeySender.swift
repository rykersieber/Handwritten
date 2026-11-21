import Foundation
import CoreGraphics
import Carbon.HIToolbox

/// Posts real keyboard events. Every event carries our marker so the input monitor can ignore it.
final class KeySender: @unchecked Sendable {
    static let marker: Int64 = 0x48574E // "HWN"

    private let source = CGEventSource(stateID: .privateState)
    var useUnicodeOnly = false
    var newlineShift = true
    var dryRun = false

    private func post(_ code: UInt16, down: Bool, flags: CGEventFlags = [], unicode: String? = nil) {
        guard !dryRun, let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        e.flags = flags
        if let u = unicode {
            let utf16 = Array(u.utf16)
            utf16.withUnsafeBufferPointer { buf in
                e.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            }
        }
        e.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        e.post(tap: .cghidEventTap)
    }

    /// Press and release a key, holding it for `hold` seconds.
    func tap(_ code: UInt16, flags: CGEventFlags = [], unicode: String? = nil, hold: Double) {
        post(code, down: true, flags: flags, unicode: unicode)
        if hold > 0 { Thread.sleep(forTimeInterval: hold) }
        post(code, down: false, flags: flags, unicode: unicode)
    }

    func type(_ c: Character, hold: Double) {
        let str = String(c)
        if !useUnicodeOnly, let info = KeyLayout.info(c) {
            tap(info.keyCode, flags: info.shift ? .maskShift : [], unicode: str, hold: hold)
            return
        }
        // Unicode path: CGEvent accepts up to 20 UTF-16 units per event.
        let units = Array(str.utf16)
        if units.count <= 20 {
            tap(0, unicode: str, hold: hold)
        } else {
            var start = 0
            while start < units.count {
                let end = min(units.count, start + 20)
                let chunk = String(utf16CodeUnits: Array(units[start..<end]), count: end - start)
                tap(0, unicode: chunk, hold: 0.002)
                start = end
            }
        }
    }

    func perform(_ a: KeyAction, hold: Double) {
        switch a {
        case .char(let c): type(c, hold: hold)
        case .newline: tap(UInt16(kVK_Return), flags: newlineShift ? .maskShift : [], hold: hold)
        case .tab: tap(UInt16(kVK_Tab), hold: hold)
        case .backspace, .deleteSelection: tap(UInt16(kVK_Delete), hold: hold)
        case .optionBackspace: tap(UInt16(kVK_Delete), flags: .maskAlternate, hold: hold)
        case .left: tap(UInt16(kVK_LeftArrow), flags: [.maskNumericPad, .maskSecondaryFn], hold: hold)
        case .right: tap(UInt16(kVK_RightArrow), flags: [.maskNumericPad, .maskSecondaryFn], hold: hold)
        case .cmdRight: tap(UInt16(kVK_RightArrow), flags: [.maskCommand, .maskNumericPad, .maskSecondaryFn], hold: hold)
        case .forwardDelete: tap(UInt16(kVK_ForwardDelete), flags: .maskSecondaryFn, hold: hold)
        case .codeIndentSelect:
            type("x", hold: hold)
            Thread.sleep(forTimeInterval: 0.03)
            tap(UInt16(kVK_LeftArrow), flags: [.maskCommand, .maskShift, .maskNumericPad, .maskSecondaryFn], hold: hold)
        case .wait: break
        }
    }

    func selectAll() { tap(UInt16(kVK_ANSI_A), flags: .maskCommand, hold: 0.03) }
    func copy() { tap(UInt16(kVK_ANSI_C), flags: .maskCommand, hold: 0.03) }
}
