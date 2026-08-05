import AppKit
import ApplicationServices

/// 포커스된 창을 인접 스페이스(이전/다음)로 옮기고 화면도 그쪽으로 전환한다.
///
/// macOS 26 Tahoe에서 창 이동은 yabai v7.1.25가 발견한 bridged 연산
/// (`SLSPerformAsynchronousBridgedWindowManagementOperation`)으로 수행한다.
/// 옛 SLSMoveWindowsToManagedSpace / CGSAddWindowsToSpaces 는 SIP 하에서
/// 무효화됐다. 이동 후 화면 전환은 옮긴 창을 raise/activate 해서 macOS가
/// 스스로 그 space로 넘어가게 한다(Dock 주도라 안전).
/// 합성 CGEvent ⌃화살표는 WindowServer가 차단하고, bridged SetCurrentSpace
/// 직접 호출은 Dock과 어긋나 화면이 깨지므로 쓰지 않는다.
enum SpaceMover {
    private static var warnedUnavailable = false

    // type 0 = 일반 Desktop Space (fullscreen 등은 target에서 제외)
    private static let userSpaceType = 0

    private struct DisplayLayout {
        let userSpaces: [CGSPrivate.SpaceID]
        let currentSpace: CGSPrivate.SpaceID
    }

    /// `direction` +1=다음, -1=이전. 성공 시 true.
    @discardableResult
    static func move(direction: Int) -> Bool {
        guard let window = WindowController.focusedWindow() else { return false }
        return move(window: window, direction: direction)
    }

    @discardableResult
    static func move(window: AXUIElement, direction: Int) -> Bool {
        guard CGSPrivate.bridgedAvailable,
              let cid = CGSPrivate.mainConnectionID?() else {
            warnUnavailableOnce()
            return false
        }

        // 1. focused window → CGWindowID
        var wid: CGWindowID = 0
        guard _AXUIElementGetWindow(window, &wid) == .success, wid != 0 else { return false }

        // 2~3. window가 속한 space + 그 space가 있는 display layout
        guard let currentSpace = spaceID(forWindow: wid, cid: cid),
              let layout = displayLayout(containing: currentSpace, cid: cid) else {
            return false
        }

        // 4. target space 결정 (no wrap)
        guard let idx = layout.userSpaces.firstIndex(of: currentSpace) else { return false }
        let targetIdx = idx + direction
        guard targetIdx >= 0, targetIdx < layout.userSpaces.count else {
            return false  // 끝에서는 멈춤
        }
        let target = layout.userSpaces[targetIdx]
        guard target != currentSpace else { return false }

        // 5. 이동 (bridged, 비동기) — 커밋될 때까지 잠깐 폴링으로 확인.
        guard CGSPrivate.bridgedMove(windowIDs: [wid], to: target) else { return false }
        var moved = false
        for _ in 0..<20 {
            usleep(25_000)
            if spaceID(forWindow: wid, cid: cid) == target { moved = true; break }
        }
        guard moved else { return false }

        // 6. 화면 전환 (창 따라가기) — 옮긴 창을 raise/activate 하면 macOS가
        //    Dock 주도의 정상 경로로 해당 space로 전환해준다.
        //    (bridged SetCurrentSpace 는 Dock과 동기화되지 않아 화면이 깨진다.)
        followWindow(window)
        return true
    }

    // MARK: - WindowSpaceResolver

    private static func spaceID(forWindow wid: CGWindowID, cid: CGSPrivate.ConnID) -> CGSPrivate.SpaceID? {
        let widArray = [NSNumber(value: wid)] as CFArray
        guard let ref = CGSPrivate.copySpacesForWindows?(cid, 7, widArray)?.takeRetainedValue(),
              let spaces = ref as? [NSNumber] else { return nil }
        return spaces.first?.uint64Value
    }

    // MARK: - SpaceProvider

    private static func displayLayout(containing space: CGSPrivate.SpaceID,
                                      cid: CGSPrivate.ConnID) -> DisplayLayout? {
        guard let ref = CGSPrivate.copyManagedDisplaySpaces?(cid)?.takeRetainedValue(),
              let displays = ref as? [[String: Any]] else { return nil }

        for display in displays {
            guard let spaceDicts = display["Spaces"] as? [[String: Any]] else { continue }
            let userSpaces: [CGSPrivate.SpaceID] = spaceDicts.compactMap { dict in
                guard let id = dict["id64"] as? NSNumber else { return nil }
                let type = (dict["type"] as? NSNumber)?.intValue ?? userSpaceType
                return type == userSpaceType ? id.uint64Value : nil
            }
            guard userSpaces.contains(space) else { continue }
            let current = (display["Current Space"] as? [String: Any])?["id64"] as? NSNumber
            return DisplayLayout(userSpaces: userSpaces,
                                 currentSpace: current?.uint64Value ?? space)
        }
        return nil
    }

    // MARK: - 화면 전환 (창 따라가기)

    /// 옮긴 창을 raise + 앱 activate. 포커스된 창이 다른 space에 있으면
    /// macOS가 그 space로 자동 전환한다(시스템 기본 동작, Dock 주도라 안전).
    private static func followWindow(_ win: AXUIElement) {
        AXUIElementPerformAction(win, kAXRaiseAction as CFString)
        var pid: pid_t = 0
        if AXUIElementGetPid(win, &pid) == .success,
           let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
    }

    private static func warnUnavailableOnce() {
        guard !warnedUnavailable else { return }
        warnedUnavailable = true
        NSLog("MWM: 스페이스 이동 비공개 API를 사용할 수 없습니다(OS 업데이트로 변경됐을 수 있음).")
    }
}
