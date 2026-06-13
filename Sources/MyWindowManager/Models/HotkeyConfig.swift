import Foundation
import HotKey
import Carbon.HIToolbox

struct HotkeyConfig: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    var hotKey: (key: Key, mods: NSEvent.ModifierFlags)? {
        guard let key = Key(carbonKeyCode: keyCode) else { return nil }
        return (key, NSEvent.ModifierFlags(carbonFlags: modifiers))
    }

    var displayString: String {
        var s = ""
        let m = NSEvent.ModifierFlags(carbonFlags: modifiers)
        if m.contains(.control) { s += "\u{2303}" }
        if m.contains(.option) { s += "\u{2325}" }
        if m.contains(.shift) { s += "\u{21E7}" }
        if m.contains(.command) { s += "\u{2318}" }
        if let key = Key(carbonKeyCode: keyCode) {
            s += key.description
        } else {
            s += "?"
        }
        return s
    }

    static func from(event: NSEvent) -> HotkeyConfig? {
        let carbonMods = event.modifierFlags.carbonFlags
        guard carbonMods != 0 else { return nil }
        return HotkeyConfig(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonMods
        )
    }
}

import AppKit

extension NSEvent.ModifierFlags {
    var carbonFlags: UInt32 {
        var f: UInt32 = 0
        if contains(.command) { f |= UInt32(cmdKey) }
        if contains(.option) { f |= UInt32(optionKey) }
        if contains(.control) { f |= UInt32(controlKey) }
        if contains(.shift) { f |= UInt32(shiftKey) }
        return f
    }

    init(carbonFlags: UInt32) {
        var f: NSEvent.ModifierFlags = []
        if carbonFlags & UInt32(cmdKey) != 0 { f.insert(.command) }
        if carbonFlags & UInt32(optionKey) != 0 { f.insert(.option) }
        if carbonFlags & UInt32(controlKey) != 0 { f.insert(.control) }
        if carbonFlags & UInt32(shiftKey) != 0 { f.insert(.shift) }
        self = f
    }
}
