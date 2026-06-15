import AppKit
import ApplicationServices

enum DisplayMover {
    /// 포커스된 창을 인접 디스플레이로 옮긴다. `direction` +1=다음, -1=이전.
    /// 순환(마지막→처음). 디스플레이가 1개면 no-op.
    @discardableResult
    static func move(direction: Int) -> Bool {
        let screens = NSScreen.screens
        guard screens.count > 1,
              let win = WindowController.focusedWindow(),
              let current = ScreenHelper.screen(containing: win),
              let frame = WindowController.getFrame(win),
              let currentIndex = screens.firstIndex(of: current) else { return false }

        let count = screens.count
        let targetIndex = ((currentIndex + direction) % count + count) % count
        let target = screens[targetIndex]

        let srcArea = ScreenHelper.placementArea(of: current)
        let dstArea = ScreenHelper.placementArea(of: target)
        guard srcArea.width > 0, srcArea.height > 0 else { return false }

        // 현재 area 기준 상대 비율 → 대상 area에 동일 비율로.
        let rx = (frame.minX - srcArea.minX) / srcArea.width
        let ry = (frame.minY - srcArea.minY) / srcArea.height
        let rw = frame.width / srcArea.width
        let rh = frame.height / srcArea.height

        let newFrame = CGRect(
            x: dstArea.minX + rx * dstArea.width,
            y: dstArea.minY + ry * dstArea.height,
            width: rw * dstArea.width,
            height: rh * dstArea.height
        )
        WindowController.setFrame(win, frame: newFrame)
        return true
    }
}
