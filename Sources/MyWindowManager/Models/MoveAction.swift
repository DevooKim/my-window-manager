import Foundation

/// 포커스된 창을 인접한 디스플레이/스페이스로 옮기는 고정 액션.
enum MoveAction: String, Codable, CaseIterable, Identifiable {
    case displayNext
    case displayPrev
    case spaceNext
    case spacePrev

    var id: String { rawValue }

    /// UI·메뉴에 표시할 이름.
    var label: String {
        switch self {
        case .displayNext: return "다음 디스플레이로"
        case .displayPrev: return "이전 디스플레이로"
        case .spaceNext:   return "다음 스페이스로"
        case .spacePrev:   return "이전 스페이스로"
        }
    }

    var isSpace: Bool { self == .spaceNext || self == .spacePrev }

    /// +1 = 다음, -1 = 이전.
    var direction: Int { (self == .displayNext || self == .spaceNext) ? 1 : -1 }
}

/// 한 이동 액션과 그에 바인딩된(선택적) 핫키.
struct MoveBinding: Codable, Hashable, Identifiable {
    var action: MoveAction
    var hotkey: HotkeyConfig?

    var id: String { action.rawValue }
}
