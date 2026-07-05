import Testing
import CoreGraphics
@testable import MyWindowManager

struct SnapZoneResolverTests {
    // Cocoa 좌표 화면 (좌하단 원점, 위 = maxY)
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let on = SnapSettings()

    // ── zone 판정 ──

    @Test func edges() {
        #expect(SnapZoneResolver.zone(cursor: CGPoint(x: 4, y: 540), screenFrame: screen, settings: on) == .leftHalf)
        #expect(SnapZoneResolver.zone(cursor: CGPoint(x: 1916, y: 540), screenFrame: screen, settings: on) == .rightHalf)
        #expect(SnapZoneResolver.zone(cursor: CGPoint(x: 960, y: 1076), screenFrame: screen, settings: on) == .maximize)
        #expect(SnapZoneResolver.zone(cursor: CGPoint(x: 960, y: 4), screenFrame: screen, settings: on) == .bottomHalf)
    }

    @Test func centerAndBeyondThresholdIsNil() {
        #expect(SnapZoneResolver.zone(cursor: CGPoint(x: 960, y: 540), screenFrame: screen, settings: on) == nil)
        #expect(SnapZoneResolver.zone(cursor: CGPoint(x: 10, y: 540), screenFrame: screen, settings: on) == nil) // 8px 초과
    }

    @Test func cornersTakePriority() {
        // 왼쪽 가장자리의 위쪽 끝 128px 구간 → 좌상단 쿼터 (Cocoa 위 = maxY 근처)
        #expect(SnapZoneResolver.zone(cursor: CGPoint(x: 4, y: 1000), screenFrame: screen, settings: on) == .topLeftQuarter)
        // 위 가장자리의 왼쪽 끝 128px 구간 → 좌상단 쿼터
        #expect(SnapZoneResolver.zone(cursor: CGPoint(x: 100, y: 1078), screenFrame: screen, settings: on) == .topLeftQuarter)
        #expect(SnapZoneResolver.zone(cursor: CGPoint(x: 4, y: 100), screenFrame: screen, settings: on) == .bottomLeftQuarter)
        #expect(SnapZoneResolver.zone(cursor: CGPoint(x: 1916, y: 1000), screenFrame: screen, settings: on) == .topRightQuarter)
        #expect(SnapZoneResolver.zone(cursor: CGPoint(x: 1900, y: 4), screenFrame: screen, settings: on) == .bottomRightQuarter)
    }

    @Test func cornersOffFallsBackToNearestEdge() {
        var s = SnapSettings()
        s.corners = false
        // (4, 1000): 왼쪽까지 4px, 위까지 80px → 더 가까운 왼쪽 엣지 규칙
        #expect(SnapZoneResolver.zone(cursor: CGPoint(x: 4, y: 1000), screenFrame: screen, settings: s) == .leftHalf)
    }

    @Test func disabledEdgeReturnsNil() {
        var s = SnapSettings()
        s.edgeTop = false
        #expect(SnapZoneResolver.zone(cursor: CGPoint(x: 960, y: 1076), screenFrame: screen, settings: s) == nil)

        var s2 = SnapSettings()
        s2.corners = false
        s2.edgeLeft = false
        #expect(SnapZoneResolver.zone(cursor: CGPoint(x: 4, y: 1000), screenFrame: screen, settings: s2) == nil)
    }

    @Test func masterOffReturnsNil() {
        var s = SnapSettings()
        s.enabled = false
        #expect(SnapZoneResolver.zone(cursor: CGPoint(x: 4, y: 540), screenFrame: screen, settings: s) == nil)
    }

    // ── 목표 프레임 (AX 좌표: 위 = minY) ──

    let area = CGRect(x: 0, y: 25, width: 1000, height: 775)

    @Test func frames() {
        #expect(SnapZoneResolver.frame(for: .maximize, in: area) == area)
        #expect(SnapZoneResolver.frame(for: .leftHalf, in: area)
                == CGRect(x: 0, y: 25, width: 500, height: 775))
        #expect(SnapZoneResolver.frame(for: .rightHalf, in: area)
                == CGRect(x: 500, y: 25, width: 500, height: 775))
        #expect(SnapZoneResolver.frame(for: .bottomHalf, in: area)
                == CGRect(x: 0, y: 412.5, width: 1000, height: 387.5))
        #expect(SnapZoneResolver.frame(for: .topLeftQuarter, in: area)
                == CGRect(x: 0, y: 25, width: 500, height: 387.5))
        #expect(SnapZoneResolver.frame(for: .topRightQuarter, in: area)
                == CGRect(x: 500, y: 25, width: 500, height: 387.5))
        #expect(SnapZoneResolver.frame(for: .bottomLeftQuarter, in: area)
                == CGRect(x: 0, y: 412.5, width: 500, height: 387.5))
        #expect(SnapZoneResolver.frame(for: .bottomRightQuarter, in: area)
                == CGRect(x: 500, y: 412.5, width: 500, height: 387.5))
    }
}
