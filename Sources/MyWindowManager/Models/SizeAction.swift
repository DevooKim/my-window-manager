import Foundation

/// 포커스된 창을 화면 크기의 일정 비율만큼 키우거나 줄이는 고정 액션.
enum SizeAction: String, Codable, CaseIterable, Identifiable {
    case grow
    case shrink

    var id: String { rawValue }

    /// UI·메뉴에 표시할 이름.
    var label: String {
        switch self {
        case .grow:   return "창 확대"
        case .shrink: return "창 축소"
        }
    }
}

/// 한 크기 액션과 그에 바인딩된(선택적) 핫키.
struct SizeBinding: Codable, Hashable, Identifiable {
    var action: SizeAction
    var hotkey: HotkeyConfig?

    var id: String { action.rawValue }
}
