import Foundation
import Carbon.HIToolbox

/// A starter hotkey scheme chosen on first launch. Each scheme maps the same
/// set of general-purpose window slots to key bindings that match a popular
/// window manager, so users coming from those tools feel at home.
enum PresetScheme: String, CaseIterable, Identifiable {
    case rectangle
    case magnet
    case vim

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rectangle: return "Rectangle 스타일"
        case .magnet:    return "Magnet 스타일"
        case .vim:       return "Vim 스타일 (HJKL)"
        }
    }

    var subtitle: String {
        switch self {
        case .rectangle: return "⌃⌥ + 화살표 · U I J K · Return"
        case .magnet:    return "⌃⌥ + 화살표 · U I J K · Return"
        case .vim:       return "⌃⌥ + H J K L · Y O B N · M"
        }
    }
}

/// One window slot: a name + frame shared across all schemes, plus the
/// per-scheme key code used to trigger it (modifiers are always ⌃⌥).
private struct Slot {
    let name: String
    let frame: RelativeFrame
    /// Key code per scheme; nil means "no default hotkey in that scheme".
    let keys: [PresetScheme: Int]
}

enum StarterPresets {
    private static let mods = UInt32(controlKey | optionKey)

    // Frames -------------------------------------------------------------
    private static func half(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> RelativeFrame {
        RelativeFrame(x: .ratio(x), y: .ratio(y), width: .ratio(w), height: .ratio(h))
    }

    private static let slots: [Slot] = [
        Slot(name: "Left Half",  frame: half(0, 0, 0.5, 1.0),
             keys: [.rectangle: kVK_LeftArrow, .magnet: kVK_LeftArrow, .vim: kVK_ANSI_H]),
        Slot(name: "Right Half", frame: half(0.5, 0, 0.5, 1.0),
             keys: [.rectangle: kVK_RightArrow, .magnet: kVK_RightArrow, .vim: kVK_ANSI_L]),
        Slot(name: "Top Half",   frame: half(0, 0, 1.0, 0.5),
             keys: [.rectangle: kVK_UpArrow, .magnet: kVK_UpArrow, .vim: kVK_ANSI_K]),
        Slot(name: "Bottom Half", frame: half(0, 0.5, 1.0, 0.5),
             keys: [.rectangle: kVK_DownArrow, .magnet: kVK_DownArrow, .vim: kVK_ANSI_J]),
        Slot(name: "Maximize",   frame: .fullScreen,
             keys: [.rectangle: kVK_Return, .magnet: kVK_Return, .vim: kVK_ANSI_M]),
        Slot(name: "Center",     frame: half(0.15, 0.15, 0.7, 0.7),
             keys: [.rectangle: kVK_ANSI_C, .vim: kVK_ANSI_C]),
        Slot(name: "Top Left",     frame: half(0, 0, 0.5, 0.5),
             keys: [.rectangle: kVK_ANSI_U, .magnet: kVK_ANSI_U, .vim: kVK_ANSI_Y]),
        Slot(name: "Top Right",    frame: half(0.5, 0, 0.5, 0.5),
             keys: [.rectangle: kVK_ANSI_I, .magnet: kVK_ANSI_I, .vim: kVK_ANSI_O]),
        Slot(name: "Bottom Left",  frame: half(0, 0.5, 0.5, 0.5),
             keys: [.rectangle: kVK_ANSI_J, .magnet: kVK_ANSI_J, .vim: kVK_ANSI_B]),
        Slot(name: "Bottom Right", frame: half(0.5, 0.5, 0.5, 0.5),
             keys: [.rectangle: kVK_ANSI_K, .magnet: kVK_ANSI_K, .vim: kVK_ANSI_N]),
    ]

    /// Build the starter preset list for a chosen scheme.
    static func presets(for scheme: PresetScheme) -> [ResizePreset] {
        slots.map { slot in
            let hotkey = slot.keys[scheme].map {
                HotkeyConfig(keyCode: UInt32($0), modifiers: mods)
            }
            return ResizePreset(name: slot.name, frame: slot.frame, hotkey: hotkey)
        }
    }
}
