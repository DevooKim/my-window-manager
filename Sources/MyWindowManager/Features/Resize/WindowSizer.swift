import AppKit
import ApplicationServices

/// 포커스 창을 화면(placementArea) 크기의 일정 비율만큼 키우거나 줄인다.
/// 앵커는 창 중심. 커지다 area를 벗어나면 안쪽으로 밀어 넣는다.
enum WindowSizer {
    static let minWidth: CGFloat = 200
    static let minHeight: CGFloat = 150

    /// 순수 계산 — `current`를 `area` 크기의 `ratio`만큼 증감한 프레임.
    static func steppedFrame(current: CGRect, area: CGRect,
                             ratio: Double, grow: Bool) -> CGRect {
        let sign: CGFloat = grow ? 1 : -1
        let newW = min(max(current.width + area.width * CGFloat(ratio) * sign, minWidth), area.width)
        let newH = min(max(current.height + area.height * CGFloat(ratio) * sign, minHeight), area.height)
        let newX = min(max(current.midX - newW / 2, area.minX), area.maxX - newW)
        let newY = min(max(current.midY - newH / 2, area.minY), area.maxY - newH)
        return CGRect(x: newX, y: newY, width: newW, height: newH)
    }

    /// 포커스 창에 적용. 창이 없으면 no-op(false).
    @discardableResult
    static func step(_ action: SizeAction, ratio: Double) -> Bool {
        guard let window = WindowController.focusedWindow() else { return false }
        return step(action, window: window, ratio: ratio)
    }

    @discardableResult
    static func step(
        _ action: SizeAction,
        window: AXUIElement,
        ratio: Double
    ) -> Bool {
        guard let screen = ScreenHelper.screen(containing: window),
              let frame = WindowController.getFrame(window) else { return false }
        let area = ScreenHelper.placementArea(of: screen)
        let target = steppedFrame(current: frame, area: area,
                                  ratio: ratio, grow: action == .grow)
        WindowController.setFrame(window, frame: target)
        return true
    }
}
