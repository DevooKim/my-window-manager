import Foundation

/// How the on-screen HUD looks while cycling through a preset cycle.
enum CycleHUDStyle: String, Codable, CaseIterable, Identifiable {
    case off
    case list
    case thumbnails

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "끄기"
        case .list: return "목록"
        case .thumbnails: return "썸네일"
        }
    }
}
