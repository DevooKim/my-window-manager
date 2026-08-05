import AppKit
import ApplicationServices

enum DisplayMover {
    /// 포커스된 창을 인접 디스플레이로 옮긴다. `direction` +1=다음, -1=이전.
    /// 순환(마지막→처음). 디스플레이가 1개면 no-op.
    @discardableResult
    static func move(direction: Int) -> Bool {
        guard let window = WindowController.focusedWindow() else { return false }
        return move(window: window, direction: direction)
    }

    @discardableResult
    static func move(window: AXUIElement, direction: Int) -> Bool {
        let screens = NSScreen.screens
        guard screens.count > 1,
              let current = ScreenHelper.screen(containing: window),
              let frame = WindowController.getFrame(window),
              let currentIndex = screens.firstIndex(of: current) else { return false }

        let count = screens.count
        let targetIndex = ((currentIndex + direction) % count + count) % count
        let target = screens[targetIndex]

        let srcArea = ScreenHelper.placementArea(of: current)
        let dstArea = ScreenHelper.placementArea(of: target)
        guard srcArea.width > 0, srcArea.height > 0 else { return false }

        // source area 대비 상대 사각형(0~1)을 그대로 대상 area에 매핑한다.
        // 화면 크기가 달라도 "왼쪽 절반=왼쪽 절반, 최대화=최대화"가 유지되고
        // 왕복해도 오차가 누적되지 않는다.
        //
        // 단, 터미널 등은 창 크기를 셀 그리드로 스냅해 area를 픽셀 단위로 딱
        // 못 채운다(예: 1920 area에 1705). 그런 "거의 붙은 변"은 완전히 붙은
        // 것으로 간주(snapEdge)해야, 대상 화면에서도 area를 꽉 채우려 시도하고
        // 미세 부족분(0.888 같은 비율)을 왕복 내내 물고 다니지 않는다.
        let rx = snapEdge((frame.minX - srcArea.minX) / srcArea.width)
        let ry = snapEdge((frame.minY - srcArea.minY) / srcArea.height)
        let rMaxX = snapEdge((frame.maxX - srcArea.minX) / srcArea.width)
        let rMaxY = snapEdge((frame.maxY - srcArea.minY) / srcArea.height)

        let newFrame = CGRect(
            x: dstArea.minX + rx * dstArea.width,
            y: dstArea.minY + ry * dstArea.height,
            width: (rMaxX - rx) * dstArea.width,
            height: (rMaxY - ry) * dstArea.height
        )
        // 창이 다른 화면으로 넘어가는 순간 첫 setFrame은 크기가 옛 화면 기준으로
        // 잘릴 수 있다(예: 1920 요청 → 1705). 한 번 더 설정해 대상 화면 기준으로
        // 반영시킨다.
        WindowController.setFrame(window, frame: newFrame)
        usleep(30_000)
        WindowController.setFrame(window, frame: newFrame)
        return true
    }

    /// 상대 좌표(0~1)를 0/0.5/1 앵커 근처면 그 값으로 스냅, 아니면 [0,1] 클램프.
    /// 그리드-스냅 앱이 area를 픽셀 단위로 못 채워 생기는 미세 오차를 흡수한다.
    /// snapPx(≈24px)를 area 폭으로 나눈 비율을 tolerance로 쓴다.
    private static func snapEdge(_ v: CGFloat, tolerance: CGFloat = 0.02) -> CGFloat {
        for anchor: CGFloat in [0, 0.5, 1] where abs(v - anchor) <= tolerance { return anchor }
        return Swift.max(0, Swift.min(1, v))
    }
}
