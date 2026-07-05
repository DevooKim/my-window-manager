import AppKit
import ApplicationServices

/// 전역 마우스 이벤트로 "창 드래그 → 가장자리 스냅"을 구현한다.
@MainActor
final class DragSnapMonitor {
    private var settings: SnapSettings
    private var monitors: [Any] = []
    private let overlay = SnapPreviewOverlay()
    private let restore = SnapRestoreStore()

    // ── 드래그 세션 상태 (mouseDown ~ mouseUp) ──
    private var mouseDownLocation: CGPoint?
    private var sessionDead = false      // hit-test 실패 등 — 이번 드래그 무시
    private var window: AXUIElement?
    private var windowID: CGWindowID?
    private var initialFrame: CGRect?    // 창 탐색 시점의 프레임(AX)
    private var dragConfirmed = false
    private var restoreHandled = false
    private var currentZone: SnapZone?
    private var currentScreen: NSScreen?
    private var lastPoll: TimeInterval = 0

    private static let dragStartDistance: CGFloat = 4
    private static let unsnapDistance: CGFloat = 10
    private static let pollInterval: TimeInterval = 0.05

    init(settings: SnapSettings) {
        self.settings = settings
    }

    var isRunning: Bool { !monitors.isEmpty }

    /// 설정/권한 변화에 맞춰 모니터를 시작·중지한다.
    func update(settings: SnapSettings, axTrusted: Bool) {
        self.settings = settings
        let shouldRun = settings.enabled && axTrusted
        if shouldRun, !isRunning { start() }
        if !shouldRun, isRunning { stop() }
    }

    private func start() {
        guard monitors.isEmpty else { return }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            self?.handleMouseDown()
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in
            self?.handleMouseDragged()
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            self?.handleMouseUp()
        }) { monitors.append(m) }
    }

    private func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        overlay.hide()
        resetSession()
    }

    // MARK: - 이벤트 처리

    private func handleMouseDown() {
        resetSession()
        mouseDownLocation = NSEvent.mouseLocation
    }

    private func handleMouseDragged() {
        guard !sessionDead else { return }
        guard let downAt = mouseDownLocation else {
            // 모니터 시작 전에 시작된 드래그 — 이번 세션은 무시.
            sessionDead = true
            return
        }
        let cursor = NSEvent.mouseLocation

        // 1) 드래그가 살짝 진행된 뒤, mouseDown 지점의 창을 한 번만 찾는다.
        if window == nil {
            guard hypot(cursor.x - downAt.x, cursor.y - downAt.y) >= Self.dragStartDistance else { return }
            guard let hit = Self.hitTestWindow(atCocoa: downAt) else {
                sessionDead = true
                return
            }
            window = hit.window
            windowID = hit.windowID
            initialFrame = hit.frame
        }

        // 2) 50ms 스로틀로 창 프레임 폴링 — 창이 실제로 움직여야 "창 드래그".
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPoll >= Self.pollInterval else { return }
        lastPoll = now

        guard let win = window, let frame = WindowController.getFrame(win) else { return }
        if !dragConfirmed {
            guard let initial = initialFrame,
                  abs(frame.minX - initial.minX) > 1 || abs(frame.minY - initial.minY) > 1
            else { return }
            dragConfirmed = true
        }

        // 3) 스냅 해제 크기 복원 — 세션당 한 번만 시도.
        if settings.restoreOnUnsnap, !restoreHandled, let id = windowID {
            restoreHandled = handleRestore(windowID: id, currentFrame: frame, win: win)
        }

        // 4) zone 판정 + 미리보기.
        updateZone(cursor: cursor)
    }

    private func handleMouseUp() {
        defer {
            overlay.hide()
            resetSession()
        }
        guard dragConfirmed, let win = window else { return }
        // 스로틀된 드래그 상태 대신 최종 커서 위치로 zone을 다시 판정한다.
        let cursor = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(cursor, $0.frame, false) }),
              let zone = SnapZoneResolver.zone(cursor: cursor, screenFrame: screen.frame, settings: settings),
              let frame = WindowController.getFrame(win)
        else { return }

        let target = SnapZoneResolver.frame(for: zone, in: ScreenHelper.placementArea(of: screen))
        if let id = windowID {
            restore.remember(windowID: id, preSnapSize: frame.size, snappedFrame: target)
        }
        WindowController.setFrame(win, frame: target)
    }

    // MARK: - 세부 동작

    /// 스냅됐던 창이 드래그로 충분히 벗어나면 크기만 원복한다(위치는 커서를
    /// 따라감). 반환값 true = 처리 완료(또는 대상 아님) — 세션 동안 재시도 안 함.
    private func handleRestore(windowID id: CGWindowID, currentFrame: CGRect,
                               win: AXUIElement) -> Bool {
        guard let entry = restore.entry(for: id) else { return true }
        guard let initial = initialFrame,
              Self.stillSnapped(initial, to: entry.snappedFrame) else {
            // 스냅 후 수동으로 크기가 바뀐 창 — 복원하지 않고 잊는다.
            restore.forget(id)
            return true
        }
        // 스냅 프레임에서 충분히 벗어날 때까지 대기(미세 이동으로 풀리지 않게).
        let moved = hypot(currentFrame.minX - initial.minX, currentFrame.minY - initial.minY)
        guard moved >= Self.unsnapDistance else { return false }

        WindowController.setFrame(
            win, frame: CGRect(origin: currentFrame.origin, size: entry.preSnapSize)
        )
        restore.forget(id)
        return true
    }

    private func updateZone(cursor: CGPoint) {
        guard dragConfirmed else { return }
        let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) }
        let zone = screen.flatMap {
            SnapZoneResolver.zone(cursor: cursor, screenFrame: $0.frame, settings: settings)
        }
        guard zone != currentZone || screen != currentScreen else { return }
        currentZone = zone
        currentScreen = screen

        if let zone, let screen, settings.preview {
            let target = SnapZoneResolver.frame(for: zone, in: ScreenHelper.placementArea(of: screen))
            overlay.show(axFrame: target)
        } else {
            overlay.hide()
        }
    }

    private func resetSession() {
        mouseDownLocation = nil
        sessionDead = false
        window = nil
        windowID = nil
        initialFrame = nil
        dragConfirmed = false
        restoreHandled = false
        currentZone = nil
        currentScreen = nil
        lastPoll = 0
    }

    // MARK: - AX hit-test

    /// Cocoa 좌표의 점 아래에 있는 창을 찾는다. 점을 AX 좌표로 변환해
    /// system-wide hit-test 후, 요소가 창이 아니면 kAXWindowAttribute로 창을
    /// 얻는다. windowID는 비공개 API라 실패할 수 있다(그 경우 복원만 비활성).
    private static func hitTestWindow(atCocoa p: CGPoint)
        -> (window: AXUIElement, windowID: CGWindowID?, frame: CGRect)? {
        guard let primary = NSScreen.screens.first else { return nil }
        let axPoint = CGPoint(x: p.x, y: primary.frame.maxY - p.y)

        let systemWide = AXUIElementCreateSystemWide()
        var hitRef: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide, Float(axPoint.x), Float(axPoint.y), &hitRef
        ) == .success, let hit = hitRef else { return nil }

        var win: AXUIElement?
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(hit, kAXRoleAttribute as CFString, &roleRef)
        if (roleRef as? String) == (kAXWindowRole as String) {
            win = hit
        } else {
            var winRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(hit, kAXWindowAttribute as CFString, &winRef) == .success,
               let winRef {
                win = (winRef as! AXUIElement)
            }
        }
        guard let win, let frame = WindowController.getFrame(win) else { return nil }

        var id: CGWindowID = 0
        let hasID = _AXUIElementGetWindow(win, &id) == .success
        return (win, hasID ? id : nil, frame)
    }

    /// 창이 아직 "스냅된 상태"인지. 드래그 감지 시점엔 이미 몇 px 움직였을 수
    /// 있으므로 크기는 빡빡하게(2px), 위치는 느슨하게(32px) 비교한다.
    private static func stillSnapped(_ frame: CGRect, to snapped: CGRect) -> Bool {
        abs(frame.width - snapped.width) <= 2
            && abs(frame.height - snapped.height) <= 2
            && abs(frame.minX - snapped.minX) <= 32
            && abs(frame.minY - snapped.minY) <= 32
    }
}
