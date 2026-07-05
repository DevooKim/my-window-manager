import Foundation

/// 드래그 스냅 설정. 모든 항목이 개별 on/off 가능하며 기본값은 전부 켬.
struct SnapSettings: Codable, Hashable {
    var enabled = true          // 마스터 — 꺼지면 모니터 자체를 중지
    var edgeLeft = true         // 왼쪽 가장자리 → 왼쪽 절반
    var edgeRight = true        // 오른쪽 가장자리 → 오른쪽 절반
    var edgeTop = true          // 위 가장자리 → 최대화
    var edgeBottom = true       // 아래 가장자리 → 아래 절반
    var corners = true          // 모서리 → 쿼터 스냅
    var preview = true          // 미리보기 오버레이
    var restoreOnUnsnap = true  // 스냅 해제 시 크기 복원

    init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, edgeLeft, edgeRight, edgeTop, edgeBottom,
             corners, preview, restoreOnUnsnap
    }

    // 필드가 없는(옛/부분) JSON도 기본값으로 채워 디코드된다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        edgeLeft = try c.decodeIfPresent(Bool.self, forKey: .edgeLeft) ?? true
        edgeRight = try c.decodeIfPresent(Bool.self, forKey: .edgeRight) ?? true
        edgeTop = try c.decodeIfPresent(Bool.self, forKey: .edgeTop) ?? true
        edgeBottom = try c.decodeIfPresent(Bool.self, forKey: .edgeBottom) ?? true
        corners = try c.decodeIfPresent(Bool.self, forKey: .corners) ?? true
        preview = try c.decodeIfPresent(Bool.self, forKey: .preview) ?? true
        restoreOnUnsnap = try c.decodeIfPresent(Bool.self, forKey: .restoreOnUnsnap) ?? true
    }
}
