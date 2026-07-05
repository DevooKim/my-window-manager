import Testing
import CoreGraphics
@testable import MyWindowManager

struct WindowSizerTests {
    // AX 좌표 기준 배치 영역 (메뉴바 아래 y=25부터 시작한다고 가정)
    let area = CGRect(x: 0, y: 25, width: 1000, height: 800)

    @Test func growExpandsAroundCenter() {
        let current = CGRect(x: 400, y: 300, width: 200, height: 200)
        let r = WindowSizer.steppedFrame(current: current, area: area, ratio: 0.1, grow: true)
        #expect(r.width == 300)           // 200 + 1000*0.1
        #expect(r.height == 280)          // 200 + 800*0.1
        #expect(r.midX == current.midX)   // 중심 유지
        #expect(r.midY == current.midY)
    }

    @Test func shrinkKeepsCenter() {
        let current = CGRect(x: 300, y: 200, width: 500, height: 400)
        let r = WindowSizer.steppedFrame(current: current, area: area, ratio: 0.1, grow: false)
        #expect(r.width == 400)
        #expect(r.height == 320)
        #expect(r.midX == current.midX)
        #expect(r.midY == current.midY)
    }

    @Test func growAtCornerIsPushedInside() {
        // 좌상단에 붙은 창 — 커지면 area 안쪽으로 밀려 들어와야 한다.
        let current = CGRect(x: 0, y: 25, width: 300, height: 300)
        let r = WindowSizer.steppedFrame(current: current, area: area, ratio: 0.1, grow: true)
        #expect(r.minX == area.minX)
        #expect(r.minY == area.minY)
        #expect(r.width == 400)
        #expect(r.height == 380)
    }

    @Test func growNeverExceedsArea() {
        let current = area
        let r = WindowSizer.steppedFrame(current: current, area: area, ratio: 0.1, grow: true)
        #expect(r == area)
    }

    @Test func shrinkRespectsMinimumSize() {
        let current = CGRect(x: 400, y: 300, width: 220, height: 160)
        let r = WindowSizer.steppedFrame(current: current, area: area, ratio: 0.1, grow: false)
        #expect(r.width == WindowSizer.minWidth)    // 200
        #expect(r.height == WindowSizer.minHeight)  // 150
    }
}
