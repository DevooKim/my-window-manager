import Foundation

/// A hotkey bound to an ordered list of presets. Pressing the same hotkey
/// repeatedly applies the next preset in the list, wrapping around.
/// Presets are referenced by id (reused from `ConfigStore.presets`), so
/// editing a preset is reflected wherever it appears in a cycle.
struct PresetCycle: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var presetIds: [UUID] = []
    var hotkey: HotkeyConfig?
}
