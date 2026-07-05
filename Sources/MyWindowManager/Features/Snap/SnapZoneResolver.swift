import Foundation
import CoreGraphics

/// 드래그 스냅의 목표 영역. 이름은 화면상(시각적) 위치 기준.
enum SnapZone: Equatable {
    case leftHalf, rightHalf, maximize, bottomHalf
    case topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter
}

/// 커서 위치 → zone → 목표 프레임. 순수 함수만 있어 단위 테스트 대상.
///
/// 좌표계: `zone(cursor:screenFrame:settings:)`는 Cocoa 좌표(좌하단 원점,
/// 화면 위쪽 = maxY). `frame(for:in:)`은 AX 좌표(좌상단 원점, 위쪽 = minY)의
/// `placementArea`를 받는다.
enum SnapZoneResolver {
    static let edgeThreshold: CGFloat = 8
    static let cornerLength: CGFloat = 128

    static func zone(cursor: CGPoint, screenFrame f: CGRect,
                     settings s: SnapSettings) -> SnapZone? {
        guard s.enabled else { return nil }

        let dLeft = cursor.x - f.minX
        let dRight = f.maxX - cursor.x
        let dTop = f.maxY - cursor.y      // Cocoa: 위 = maxY
        let dBottom = cursor.y - f.minY

        let nearLeft = dLeft >= 0 && dLeft <= edgeThreshold
        let nearRight = dRight >= 0 && dRight <= edgeThreshold
        let nearTop = dTop >= 0 && dTop <= edgeThreshold
        let nearBottom = dBottom >= 0 && dBottom <= edgeThreshold

        // 코너: 어떤 가장자리 위(threshold 안)이면서 그 가장자리의 끝에서
        // cornerLength 이내. 엣지보다 우선한다.
        if s.corners {
            if (nearLeft && dTop <= cornerLength) || (nearTop && dLeft <= cornerLength) {
                return .topLeftQuarter
            }
            if (nearRight && dTop <= cornerLength) || (nearTop && dRight <= cornerLength) {
                return .topRightQuarter
            }
            if (nearLeft && dBottom <= cornerLength) || (nearBottom && dLeft <= cornerLength) {
                return .bottomLeftQuarter
            }
            if (nearRight && dBottom <= cornerLength) || (nearBottom && dRight <= cornerLength) {
                return .bottomRightQuarter
            }
        }

        // 엣지: 커서에서 가장 가까운 가장자리 하나의 규칙만 적용.
        // (코너 off 폴백 포함 — 그 가장자리 토글이 꺼져 있으면 스냅 없음)
        var candidates: [(distance: CGFloat, zone: SnapZone, enabled: Bool)] = []
        if nearLeft { candidates.append((dLeft, .leftHalf, s.edgeLeft)) }
        if nearRight { candidates.append((dRight, .rightHalf, s.edgeRight)) }
        if nearTop { candidates.append((dTop, .maximize, s.edgeTop)) }
        if nearBottom { candidates.append((dBottom, .bottomHalf, s.edgeBottom)) }

        guard let best = candidates.min(by: { $0.distance < $1.distance }) else { return nil }
        return best.enabled ? best.zone : nil
    }

    /// zone의 목표 프레임. `area`는 AX 좌표의 placementArea(위 = minY).
    static func frame(for zone: SnapZone, in area: CGRect) -> CGRect {
        let w = area.width, h = area.height
        switch zone {
        case .maximize:
            return area
        case .leftHalf:
            return CGRect(x: area.minX, y: area.minY, width: w / 2, height: h)
        case .rightHalf:
            return CGRect(x: area.midX, y: area.minY, width: w / 2, height: h)
        case .bottomHalf:
            return CGRect(x: area.minX, y: area.midY, width: w, height: h / 2)
        case .topLeftQuarter:
            return CGRect(x: area.minX, y: area.minY, width: w / 2, height: h / 2)
        case .topRightQuarter:
            return CGRect(x: area.midX, y: area.minY, width: w / 2, height: h / 2)
        case .bottomLeftQuarter:
            return CGRect(x: area.minX, y: area.midY, width: w / 2, height: h / 2)
        case .bottomRightQuarter:
            return CGRect(x: area.midX, y: area.midY, width: w / 2, height: h / 2)
        }
    }
}
