import Foundation

struct ResizePreset: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var frame: RelativeFrame
    var hotkey: HotkeyConfig?
}
