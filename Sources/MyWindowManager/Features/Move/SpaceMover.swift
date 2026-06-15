import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum SpaceMover {
    private static var warnedUnavailable = false

    /// 포커스된 창을 인접 스페이스로 옮기고 화면도 전환한다.
    /// `direction` +1=다음, -1=이전. CGS 심볼이 없으면 no-op + 1회 경고.
    @discardableResult
    static func move(direction: Int) -> Bool {
        guard CGSPrivate.isAvailable,
              let cid = CGSPrivate.mainConnectionID?(),
              let getActive = CGSPrivate.getActiveSpace,
              let copySpaces = CGSPrivate.copySpaces,
              let moveWindows = CGSPrivate.moveWindowsToManagedSpace else {
            if !warnedUnavailable {
                warnedUnavailable = true
                NSLog("MWM: 스페이스 이동 비공개 API를 사용할 수 없습니다(OS 업데이트로 변경됐을 수 있음).")
            }
            return false
        }

        guard let win = WindowController.focusedWindow() else { return false }
        var wid: CGWindowID = 0
        guard _AXUIElementGetWindow(win, &wid) == .success, wid != 0 else { return false }

        // 모든 스페이스 목록(현재 연결 기준)과 현재 스페이스.
        guard let spacesRef = copySpaces(cid, 7)?.takeRetainedValue()
        else { return false }
        let spaces = (spacesRef as? [NSNumber])?.map { $0.uint64Value } ?? []
        let active = getActive(cid)
        guard let curIdx = spaces.firstIndex(of: active), spaces.count > 1 else { return false }

        let count = spaces.count
        let targetIdx = ((curIdx + direction) % count + count) % count
        let target = spaces[targetIdx]
        guard target != active else { return false }

        // 창 이동.
        let widArray = [NSNumber(value: wid)] as CFArray
        moveWindows(cid, widArray, target)

        // 화면도 같은 방향으로 전환 (Mission Control 기본 단축키 ⌃←/⌃→ 합성).
        switchSpace(direction: direction)
        return true
    }

    /// Control+Left/Right 를 합성해 인접 스페이스로 화면 전환.
    /// (시스템 설정 > 키보드 > Mission Control 에서 해당 단축키가 켜져 있어야 동작.)
    private static func switchSpace(direction: Int) {
        let keyCode: CGKeyCode = direction > 0
            ? CGKeyCode(kVK_RightArrow) : CGKeyCode(kVK_LeftArrow)
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = .maskControl
        up.flags = .maskControl
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
