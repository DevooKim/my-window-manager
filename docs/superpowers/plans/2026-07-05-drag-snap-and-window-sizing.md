# 드래그 스냅 + 창 확대/축소 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 창을 드래그해 화면 가장자리/모서리에 붙이면 자동 리사이즈되는 드래그 스냅과, 핫키로 창을 화면 크기의 N%씩 키우고 줄이는 확대/축소 기능을 추가한다.

**Architecture:** 전역 NSEvent 모니터 + AX hit-test로 창 드래그 세션을 감지하고, 순수 함수(`SnapZoneResolver`)가 커서 위치 → zone → 목표 프레임을 계산한다. 확대/축소는 기존 `MoveBinding` 패턴을 그대로 따르는 고정 액션(`SizeAction`) + `HotkeyRegistry` 등록이다. 설정은 `AppConfig`에 `decodeIfPresent` + 기본값으로 추가해 기존 config와 하위호환.

**Tech Stack:** Swift 5.9 SPM(executable target), AppKit, ApplicationServices(AX), XCTest(신규 테스트 타깃), 기존 HotKey 라이브러리.

**스펙:** `docs/superpowers/specs/2026-07-05-drag-snap-and-window-sizing-design.md`

**중요 — 프로젝트 규칙:**
- 빌드: `swift build`, 테스트: `swift test`, 앱 번들+실행: `make run` (저장소 루트에서).
- 모든 커밋 메시지는 기존 스타일(`feat:`, `docs:`, `chore:`)을 따른다.
- 좌표계 주의: AX(접근성)는 **좌상단 원점, y 아래로 증가**. Cocoa(NSScreen/NSEvent)는 **좌하단 원점, y 위로 증가**. 변환은 항상 primary 스크린(`NSScreen.screens.first`) 기준. 기존 `ScreenHelper.axVisibleFrame` 참고.

---

### Task 1: 테스트 타깃 신설 + SizeAction 모델 + WindowSizer 계산 (TDD)

**Files:**
- Modify: `Package.swift`
- Create: `Tests/MyWindowManagerTests/WindowSizerTests.swift`
- Create: `Sources/MyWindowManager/Models/SizeAction.swift`
- Create: `Sources/MyWindowManager/Features/Resize/WindowSizer.swift`

- [ ] **Step 1: Package.swift에 테스트 타깃 추가**

`Package.swift` 전체를 다음으로 교체:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyWindowManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MyWindowManager", targets: ["MyWindowManager"])
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0")
    ],
    targets: [
        .executableTarget(
            name: "MyWindowManager",
            dependencies: ["HotKey"],
            path: "Sources/MyWindowManager"
        ),
        .testTarget(
            name: "MyWindowManagerTests",
            dependencies: ["MyWindowManager"],
            path: "Tests/MyWindowManagerTests"
        )
    ]
)
```

- [ ] **Step 2: 실패하는 테스트 작성**

`Tests/MyWindowManagerTests/WindowSizerTests.swift` 생성:

```swift
import XCTest
@testable import MyWindowManager

final class WindowSizerTests: XCTestCase {
    // AX 좌표 기준 배치 영역 (메뉴바 아래 y=25부터 시작한다고 가정)
    let area = CGRect(x: 0, y: 25, width: 1000, height: 800)

    func testGrowExpandsAroundCenter() {
        let current = CGRect(x: 400, y: 300, width: 200, height: 200)
        let r = WindowSizer.steppedFrame(current: current, area: area, ratio: 0.1, grow: true)
        XCTAssertEqual(r.width, 300)          // 200 + 1000*0.1
        XCTAssertEqual(r.height, 280)         // 200 + 800*0.1
        XCTAssertEqual(r.midX, current.midX)  // 중심 유지
        XCTAssertEqual(r.midY, current.midY)
    }

    func testShrinkKeepsCenter() {
        let current = CGRect(x: 300, y: 200, width: 500, height: 400)
        let r = WindowSizer.steppedFrame(current: current, area: area, ratio: 0.1, grow: false)
        XCTAssertEqual(r.width, 400)
        XCTAssertEqual(r.height, 320)
        XCTAssertEqual(r.midX, current.midX)
        XCTAssertEqual(r.midY, current.midY)
    }

    func testGrowAtCornerIsPushedInside() {
        // 좌상단에 붙은 창 — 커지면 area 안쪽으로 밀려 들어와야 한다.
        let current = CGRect(x: 0, y: 25, width: 300, height: 300)
        let r = WindowSizer.steppedFrame(current: current, area: area, ratio: 0.1, grow: true)
        XCTAssertEqual(r.minX, area.minX)
        XCTAssertEqual(r.minY, area.minY)
        XCTAssertEqual(r.width, 400)
        XCTAssertEqual(r.height, 380)
    }

    func testGrowNeverExceedsArea() {
        let current = area
        let r = WindowSizer.steppedFrame(current: current, area: area, ratio: 0.1, grow: true)
        XCTAssertEqual(r, area)
    }

    func testShrinkRespectsMinimumSize() {
        let current = CGRect(x: 400, y: 300, width: 220, height: 160)
        let r = WindowSizer.steppedFrame(current: current, area: area, ratio: 0.1, grow: false)
        XCTAssertEqual(r.width, WindowSizer.minWidth)    // 200
        XCTAssertEqual(r.height, WindowSizer.minHeight)  // 150
    }
}
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `swift test`
Expected: **컴파일 에러** — `cannot find 'WindowSizer' in scope` (테스트 타깃 자체는 인식되어야 한다. `no such module 'MyWindowManager'`가 나오면 Package.swift의 path/이름 오타 확인)

- [ ] **Step 4: 모델 + 최소 구현**

`Sources/MyWindowManager/Models/SizeAction.swift` 생성:

```swift
import Foundation

/// 포커스된 창을 화면 크기의 일정 비율만큼 키우거나 줄이는 고정 액션.
enum SizeAction: String, Codable, CaseIterable, Identifiable {
    case grow
    case shrink

    var id: String { rawValue }

    /// UI·메뉴에 표시할 이름.
    var label: String {
        switch self {
        case .grow:   return "창 확대"
        case .shrink: return "창 축소"
        }
    }
}

/// 한 크기 액션과 그에 바인딩된(선택적) 핫키.
struct SizeBinding: Codable, Hashable, Identifiable {
    var action: SizeAction
    var hotkey: HotkeyConfig?

    var id: String { action.rawValue }
}
```

`Sources/MyWindowManager/Features/Resize/WindowSizer.swift` 생성:

```swift
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
        guard let win = WindowController.focusedWindow(),
              let screen = ScreenHelper.screen(containing: win),
              let frame = WindowController.getFrame(win) else { return false }
        let area = ScreenHelper.placementArea(of: screen)
        let target = steppedFrame(current: frame, area: area,
                                  ratio: ratio, grow: action == .grow)
        WindowController.setFrame(win, frame: target)
        return true
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `swift test`
Expected: `Test Suite 'All tests' passed` — 5 tests, 0 failures

- [ ] **Step 6: Commit**

```bash
git add Package.swift Tests/ Sources/MyWindowManager/Models/SizeAction.swift Sources/MyWindowManager/Features/Resize/WindowSizer.swift
git commit -m "feat: window grow/shrink calculation + test target bootstrap"
```

---

### Task 2: SnapSettings 모델 (TDD)

**Files:**
- Create: `Sources/MyWindowManager/Models/SnapSettings.swift`
- Create: `Tests/MyWindowManagerTests/SnapSettingsTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/MyWindowManagerTests/SnapSettingsTests.swift` 생성:

```swift
import XCTest
@testable import MyWindowManager

final class SnapSettingsTests: XCTestCase {
    func testDefaultsAreAllOn() {
        let s = SnapSettings()
        XCTAssertTrue(s.enabled)
        XCTAssertTrue(s.edgeLeft)
        XCTAssertTrue(s.edgeRight)
        XCTAssertTrue(s.edgeTop)
        XCTAssertTrue(s.edgeBottom)
        XCTAssertTrue(s.corners)
        XCTAssertTrue(s.preview)
        XCTAssertTrue(s.restoreOnUnsnap)
    }

    // 필드가 일부만 있는 JSON(장래 필드 추가 대비)도 기본값으로 채워져야 한다.
    func testDecodesPartialJSON() throws {
        let json = #"{"enabled":false,"corners":false}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(SnapSettings.self, from: json)
        XCTAssertFalse(s.enabled)
        XCTAssertFalse(s.corners)
        XCTAssertTrue(s.preview)
        XCTAssertTrue(s.edgeLeft)
    }

    func testRoundTrip() throws {
        var s = SnapSettings()
        s.edgeTop = false
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(SnapSettings.self, from: data)
        XCTAssertEqual(s, back)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter SnapSettingsTests`
Expected: 컴파일 에러 — `cannot find 'SnapSettings' in scope`

- [ ] **Step 3: 구현**

`Sources/MyWindowManager/Models/SnapSettings.swift` 생성:

```swift
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
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter SnapSettingsTests`
Expected: 3 tests passed

- [ ] **Step 5: Commit**

```bash
git add Sources/MyWindowManager/Models/SnapSettings.swift Tests/MyWindowManagerTests/SnapSettingsTests.swift
git commit -m "feat: SnapSettings model with per-item toggles"
```

---

### Task 3: SnapZone + SnapZoneResolver (TDD)

**Files:**
- Create: `Sources/MyWindowManager/Features/Snap/SnapZoneResolver.swift`
- Create: `Tests/MyWindowManagerTests/SnapZoneResolverTests.swift`

핵심 규칙(스펙 그대로):
- zone 판정은 **Cocoa 좌표**(커서=`NSEvent.mouseLocation`, 화면=`NSScreen.frame`). Cocoa에서 화면 위쪽 = `maxY`.
- 목표 프레임 계산은 **AX 좌표**의 `placementArea`. AX에서 위쪽 = `minY`.
- 가장자리 threshold 8px, 코너 구간 128px(가장자리 끝에서), 코너가 엣지보다 우선.
- 코너 토글 off → 커서에서 가장 가까운 가장자리의 엣지 규칙으로 폴백. 그 가장자리 토글도 off면 nil.

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/MyWindowManagerTests/SnapZoneResolverTests.swift` 생성:

```swift
import XCTest
@testable import MyWindowManager

final class SnapZoneResolverTests: XCTestCase {
    // Cocoa 좌표 화면 (좌하단 원점, 위 = maxY)
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let on = SnapSettings()

    // ── zone 판정 ──

    func testEdges() {
        XCTAssertEqual(SnapZoneResolver.zone(cursor: CGPoint(x: 4, y: 540), screenFrame: screen, settings: on), .leftHalf)
        XCTAssertEqual(SnapZoneResolver.zone(cursor: CGPoint(x: 1916, y: 540), screenFrame: screen, settings: on), .rightHalf)
        XCTAssertEqual(SnapZoneResolver.zone(cursor: CGPoint(x: 960, y: 1076), screenFrame: screen, settings: on), .maximize)
        XCTAssertEqual(SnapZoneResolver.zone(cursor: CGPoint(x: 960, y: 4), screenFrame: screen, settings: on), .bottomHalf)
    }

    func testCenterAndBeyondThresholdIsNil() {
        XCTAssertNil(SnapZoneResolver.zone(cursor: CGPoint(x: 960, y: 540), screenFrame: screen, settings: on))
        XCTAssertNil(SnapZoneResolver.zone(cursor: CGPoint(x: 10, y: 540), screenFrame: screen, settings: on)) // 8px 초과
    }

    func testCornersTakePriority() {
        // 왼쪽 가장자리의 위쪽 끝 128px 구간 → 좌상단 쿼터 (Cocoa 위 = maxY 근처)
        XCTAssertEqual(SnapZoneResolver.zone(cursor: CGPoint(x: 4, y: 1000), screenFrame: screen, settings: on), .topLeftQuarter)
        // 위 가장자리의 왼쪽 끝 128px 구간 → 좌상단 쿼터
        XCTAssertEqual(SnapZoneResolver.zone(cursor: CGPoint(x: 100, y: 1078), screenFrame: screen, settings: on), .topLeftQuarter)
        XCTAssertEqual(SnapZoneResolver.zone(cursor: CGPoint(x: 4, y: 100), screenFrame: screen, settings: on), .bottomLeftQuarter)
        XCTAssertEqual(SnapZoneResolver.zone(cursor: CGPoint(x: 1916, y: 1000), screenFrame: screen, settings: on), .topRightQuarter)
        XCTAssertEqual(SnapZoneResolver.zone(cursor: CGPoint(x: 1900, y: 4), screenFrame: screen, settings: on), .bottomRightQuarter)
    }

    func testCornersOffFallsBackToNearestEdge() {
        var s = SnapSettings()
        s.corners = false
        // (4, 1000): 왼쪽까지 4px, 위까지 80px → 더 가까운 왼쪽 엣지 규칙
        XCTAssertEqual(SnapZoneResolver.zone(cursor: CGPoint(x: 4, y: 1000), screenFrame: screen, settings: s), .leftHalf)
    }

    func testDisabledEdgeReturnsNil() {
        var s = SnapSettings()
        s.edgeTop = false
        XCTAssertNil(SnapZoneResolver.zone(cursor: CGPoint(x: 960, y: 1076), screenFrame: screen, settings: s))

        var s2 = SnapSettings()
        s2.corners = false
        s2.edgeLeft = false
        XCTAssertNil(SnapZoneResolver.zone(cursor: CGPoint(x: 4, y: 1000), screenFrame: screen, settings: s2))
    }

    func testMasterOffReturnsNil() {
        var s = SnapSettings()
        s.enabled = false
        XCTAssertNil(SnapZoneResolver.zone(cursor: CGPoint(x: 4, y: 540), screenFrame: screen, settings: s))
    }

    // ── 목표 프레임 (AX 좌표: 위 = minY) ──

    let area = CGRect(x: 0, y: 25, width: 1000, height: 775)

    func testFrames() {
        XCTAssertEqual(SnapZoneResolver.frame(for: .maximize, in: area), area)
        XCTAssertEqual(SnapZoneResolver.frame(for: .leftHalf, in: area),
                       CGRect(x: 0, y: 25, width: 500, height: 775))
        XCTAssertEqual(SnapZoneResolver.frame(for: .rightHalf, in: area),
                       CGRect(x: 500, y: 25, width: 500, height: 775))
        XCTAssertEqual(SnapZoneResolver.frame(for: .bottomHalf, in: area),
                       CGRect(x: 0, y: 412.5, width: 1000, height: 387.5))
        XCTAssertEqual(SnapZoneResolver.frame(for: .topLeftQuarter, in: area),
                       CGRect(x: 0, y: 25, width: 500, height: 387.5))
        XCTAssertEqual(SnapZoneResolver.frame(for: .topRightQuarter, in: area),
                       CGRect(x: 500, y: 25, width: 500, height: 387.5))
        XCTAssertEqual(SnapZoneResolver.frame(for: .bottomLeftQuarter, in: area),
                       CGRect(x: 0, y: 412.5, width: 500, height: 387.5))
        XCTAssertEqual(SnapZoneResolver.frame(for: .bottomRightQuarter, in: area),
                       CGRect(x: 500, y: 412.5, width: 500, height: 387.5))
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter SnapZoneResolverTests`
Expected: 컴파일 에러 — `cannot find 'SnapZoneResolver' in scope`

- [ ] **Step 3: 구현**

`Sources/MyWindowManager/Features/Snap/SnapZoneResolver.swift` 생성:

```swift
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
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter SnapZoneResolverTests`
Expected: 8 tests passed

- [ ] **Step 5: Commit**

```bash
git add Sources/MyWindowManager/Features/Snap/SnapZoneResolver.swift Tests/MyWindowManagerTests/SnapZoneResolverTests.swift
git commit -m "feat: snap zone resolution (edges, corners, toggles)"
```

---

### Task 4: AppConfig / ConfigStore 확장 (TDD)

**Files:**
- Modify: `Sources/MyWindowManager/Storage/ConfigStore.swift`
- Create: `Tests/MyWindowManagerTests/AppConfigCompatTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/MyWindowManagerTests/AppConfigCompatTests.swift` 생성:

```swift
import XCTest
@testable import MyWindowManager

final class AppConfigCompatTests: XCTestCase {
    // 기존 사용자의 v2 config.json(새 필드 없음)이 기본값으로 디코드돼야 한다.
    func testDecodingV2ConfigAppliesDefaults() throws {
        let json = #"{"version":2,"presets":[],"layouts":[],"cycles":[]}"#.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertTrue(cfg.snapSettings.enabled)
        XCTAssertTrue(cfg.snapSettings.restoreOnUnsnap)
        XCTAssertEqual(cfg.sizeBindings, [])
        XCTAssertEqual(cfg.sizeStepRatio, 0.1)
    }

    func testRoundTripKeepsNewFields() throws {
        var cfg = AppConfig(presets: [], layouts: [], cycles: [], deadzones: [])
        cfg.snapSettings.edgeTop = false
        cfg.sizeStepRatio = 0.15
        cfg.sizeBindings = [SizeBinding(action: .grow, hotkey: nil)]
        let data = try JSONEncoder().encode(cfg)
        let back = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertFalse(back.snapSettings.edgeTop)
        XCTAssertEqual(back.sizeStepRatio, 0.15)
        XCTAssertEqual(back.sizeBindings.count, 1)
        XCTAssertEqual(back.sizeBindings[0].action, .grow)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter AppConfigCompatTests`
Expected: 컴파일 에러 — `value of type 'AppConfig' has no member 'snapSettings'`

- [ ] **Step 3: AppConfig 수정**

`Sources/MyWindowManager/Storage/ConfigStore.swift`의 `struct AppConfig` 전체(1~39행 부근)를 다음으로 교체:

```swift
struct AppConfig: Codable {
    var version: Int = 3
    var presets: [ResizePreset]
    var layouts: [Layout]
    var cycles: [PresetCycle]
    var deadzones: [DisplayDeadzone]
    var cycleHUDStyle: CycleHUDStyle
    var moveBindings: [MoveBinding]
    var snapSettings: SnapSettings
    var sizeBindings: [SizeBinding]
    var sizeStepRatio: Double

    init(presets: [ResizePreset], layouts: [Layout], cycles: [PresetCycle],
         deadzones: [DisplayDeadzone], cycleHUDStyle: CycleHUDStyle = .thumbnails,
         moveBindings: [MoveBinding] = [],
         snapSettings: SnapSettings = SnapSettings(),
         sizeBindings: [SizeBinding] = [],
         sizeStepRatio: Double = 0.1) {
        self.presets = presets
        self.layouts = layouts
        self.cycles = cycles
        self.deadzones = deadzones
        self.cycleHUDStyle = cycleHUDStyle
        self.moveBindings = moveBindings
        self.snapSettings = snapSettings
        self.sizeBindings = sizeBindings
        self.sizeStepRatio = sizeStepRatio
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        presets = try c.decodeIfPresent([ResizePreset].self, forKey: .presets) ?? []
        layouts = try c.decodeIfPresent([Layout].self, forKey: .layouts) ?? []
        // `cycles` was added later — older config.json files won't have it.
        cycles = try c.decodeIfPresent([PresetCycle].self, forKey: .cycles) ?? []
        // `deadzones` added later too.
        deadzones = try c.decodeIfPresent([DisplayDeadzone].self, forKey: .deadzones) ?? []
        // `cycleHUDStyle` added later too — default to thumbnails.
        cycleHUDStyle = try c.decodeIfPresent(CycleHUDStyle.self, forKey: .cycleHUDStyle) ?? .thumbnails
        // `moveBindings` added in v2 — default to empty for older configs.
        moveBindings = try c.decodeIfPresent([MoveBinding].self, forKey: .moveBindings) ?? []
        // v3: 드래그 스냅 + 창 확대/축소.
        snapSettings = try c.decodeIfPresent(SnapSettings.self, forKey: .snapSettings) ?? SnapSettings()
        sizeBindings = try c.decodeIfPresent([SizeBinding].self, forKey: .sizeBindings) ?? []
        sizeStepRatio = try c.decodeIfPresent(Double.self, forKey: .sizeStepRatio) ?? 0.1
    }
}
```

- [ ] **Step 4: ConfigStore 프로퍼티 추가**

같은 파일 `ConfigStore` 클래스의 `@Published var moveBindings` 선언 바로 아래에 추가:

```swift
    @Published var snapSettings: SnapSettings = SnapSettings() {
        didSet { if snapSettings != oldValue { save() } }
    }
    @Published var sizeBindings: [SizeBinding] = [] {
        didSet { if sizeBindings != oldValue { save() } }
    }
    /// 창 확대/축소 스텝 — 화면 크기 대비 비율(0.02~0.30).
    @Published var sizeStepRatio: Double = 0.1 {
        didSet { if sizeStepRatio != oldValue { save() } }
    }
```

- [ ] **Step 5: load/save/export/import 반영**

`load()`의 성공 분기(`self.moveBindings = cfg.moveBindings` 다음)에 추가:

```swift
            self.snapSettings = cfg.snapSettings
            self.sizeBindings = cfg.sizeBindings
            self.sizeStepRatio = cfg.sizeStepRatio
```

`load()`의 실패 분기(`self.moveBindings = []` 다음)에 추가:

```swift
            self.snapSettings = SnapSettings()
            self.sizeBindings = []
            self.sizeStepRatio = 0.1
```

`save()`와 `export(to:)` 두 곳의 `AppConfig(...)` 생성을 다음으로 교체:

```swift
        let cfg = AppConfig(presets: presets, layouts: layouts, cycles: cycles,
                            deadzones: deadzones, cycleHUDStyle: cycleHUDStyle,
                            moveBindings: moveBindings, snapSettings: snapSettings,
                            sizeBindings: sizeBindings, sizeStepRatio: sizeStepRatio)
```

`importConfig(from:)`의 `moveBindings = cfg.moveBindings` 다음에 추가:

```swift
        snapSettings = cfg.snapSettings
        sizeBindings = cfg.sizeBindings
        sizeStepRatio = cfg.sizeStepRatio
```

- [ ] **Step 6: hotkeyConflicts에 size 바인딩 반영**

`hotkeyConflicts(for:excludingId:)`의 move 관련 블록(파일 끝부분):

```swift
        // 이동 액션은 UUID가 아니라 자기 제외가 불가능하므로, 같은 combo를 가진
        // 이동 바인딩이 2개 이상일 때만(서로 충돌) 표시한다.
        let movesWithSame = moveBindings.filter { matches($0.hotkey) }
        if movesWithSame.count > 1 {
            for b in movesWithSame {
                result.append("\(b.action.label) (이동)")
            }
        }
        return result
```

를 다음으로 교체:

```swift
        // 이동/크기 액션은 UUID가 없어 자기 제외가 불가능하므로, 같은 combo를
        // 가진 고정 액션 바인딩이 2개 이상일 때만(서로 충돌) 표시한다.
        var fixed: [String] = []
        for b in moveBindings where matches(b.hotkey) {
            fixed.append("\(b.action.label) (이동)")
        }
        for b in sizeBindings where matches(b.hotkey) {
            fixed.append("\(b.action.label) (크기)")
        }
        if fixed.count > 1 {
            result.append(contentsOf: fixed)
        }
        return result
```

- [ ] **Step 7: 전체 테스트 + 빌드 확인**

Run: `swift test && swift build`
Expected: 모든 테스트 통과, 빌드 성공

- [ ] **Step 8: Commit**

```bash
git add Sources/MyWindowManager/Storage/ConfigStore.swift Tests/MyWindowManagerTests/AppConfigCompatTests.swift
git commit -m "feat: persist snap settings + size bindings (config v3, backward compatible)"
```

---

### Task 5: HotkeyRegistry에 크기 바인딩 등록

**Files:**
- Modify: `Sources/MyWindowManager/Hotkey/HotkeyRegistry.swift`

- [ ] **Step 1: Target 케이스 추가**

`HotkeyRegistry.Target` enum에 케이스 추가:

```swift
    enum Target {
        case preset(UUID)
        case layout(UUID)
        case cycle(UUID)
        case move(MoveAction)
        case size(SizeAction)
    }
```

- [ ] **Step 2: rebuild()에 등록 루프 추가**

`rebuild()` 안, `for binding in store.moveBindings { ... }` 루프 **다음**에 추가:

```swift
        for binding in store.sizeBindings {
            guard let cfg = binding.hotkey, let hk = cfg.hotKey else { continue }
            let key = HotKey(key: hk.key, modifiers: hk.mods)
            let action = binding.action
            key.keyDownHandler = { [weak self, weak store] in
                guard let store else { return }
                self?.resetCycleState()
                WindowSizer.step(action, ratio: store.sizeStepRatio)
            }
            hotkeys.append((.size(action), key))
        }
```

- [ ] **Step 3: 빌드 + 테스트**

Run: `swift build && swift test`
Expected: 성공 (기존 테스트 영향 없음)

- [ ] **Step 4: Commit**

```bash
git add Sources/MyWindowManager/Hotkey/HotkeyRegistry.swift
git commit -m "feat: register grow/shrink hotkeys"
```

---

### Task 6: MoveView에 "창 크기" 섹션 + 탭 라벨 변경

**Files:**
- Modify: `Sources/MyWindowManager/UI/Editor/MoveView.swift` (전체 교체)
- Modify: `Sources/MyWindowManager/UI/Editor/EditorWindow.swift` (라벨 1곳)

- [ ] **Step 1: MoveView 전체 교체**

`Sources/MyWindowManager/UI/Editor/MoveView.swift` 전체를 다음으로 교체:

```swift
import SwiftUI

/// "이동·크기" 탭 — 포커스 창을 인접 디스플레이/스페이스로 옮기는 액션과
/// 창 확대/축소 액션의 핫키 설정.
struct MoveView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var hotkeys: HotkeyRegistryHolder

    var body: some View {
        Form {
            Section("디스플레이") {
                row(.displayPrev)
                row(.displayNext)
            }
            Section {
                row(.spacePrev)
                row(.spaceNext)
            } header: {
                Text("스페이스")
            } footer: {
                Text("스페이스 이동은 비공개 기능을 사용하며, 화면 전환은 시스템 설정 > 키보드 > Mission Control 의 \"한 스페이스 왼쪽/오른쪽으로 이동\" 단축키(⌃←/⌃→)가 켜져 있어야 동작합니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section {
                sizeRow(.grow)
                sizeRow(.shrink)
                HStack {
                    Text("확대/축소 비율")
                    Spacer()
                    Text("\(stepPercent.wrappedValue)%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper("", value: stepPercent, in: 2...30, step: 1)
                        .labelsHidden()
                }
            } header: {
                Text("창 크기")
            } footer: {
                Text("한 번 누를 때마다 화면 크기의 위 비율만큼 창이 커지거나 작아집니다. 기준점은 창 중심입니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func row(_ action: MoveAction) -> some View {
        let binding = hotkeyBinding(for: action)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(action.label)
                Spacer()
                HotkeyCaptureView(hotkey: binding)
            }
            HotkeyConflictWarning(hotkey: binding.wrappedValue, selfId: nil)
        }
    }

    @ViewBuilder
    private func sizeRow(_ action: SizeAction) -> some View {
        let binding = sizeHotkeyBinding(for: action)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(action.label)
                Spacer()
                HotkeyCaptureView(hotkey: binding)
            }
            HotkeyConflictWarning(hotkey: binding.wrappedValue, selfId: nil)
        }
    }

    /// 해당 액션의 핫키에 대한 양방향 바인딩. 없으면 빈 바인딩을 만들어 둔다.
    private func hotkeyBinding(for action: MoveAction) -> Binding<HotkeyConfig?> {
        Binding(
            get: { store.moveBindings.first { $0.action == action }?.hotkey },
            set: { newValue in
                var list = store.moveBindings
                if let i = list.firstIndex(where: { $0.action == action }) {
                    list[i].hotkey = newValue
                } else {
                    list.append(MoveBinding(action: action, hotkey: newValue))
                }
                store.moveBindings = list
                hotkeys.registry.rebuild()
            }
        )
    }

    private func sizeHotkeyBinding(for action: SizeAction) -> Binding<HotkeyConfig?> {
        Binding(
            get: { store.sizeBindings.first { $0.action == action }?.hotkey },
            set: { newValue in
                var list = store.sizeBindings
                if let i = list.firstIndex(where: { $0.action == action }) {
                    list[i].hotkey = newValue
                } else {
                    list.append(SizeBinding(action: action, hotkey: newValue))
                }
                store.sizeBindings = list
                hotkeys.registry.rebuild()
            }
        )
    }

    /// sizeStepRatio(0.02~0.30)를 % 정수로 노출.
    private var stepPercent: Binding<Int> {
        Binding(
            get: { Int((store.sizeStepRatio * 100).rounded()) },
            set: { store.sizeStepRatio = Double($0) / 100 }
        )
    }
}
```

- [ ] **Step 2: 탭 라벨 변경**

`Sources/MyWindowManager/UI/Editor/EditorWindow.swift`의 `case .move: return "이동"`을 다음으로 변경:

```swift
        case .move: return "이동·크기"
```

- [ ] **Step 3: 빌드**

Run: `swift build`
Expected: 성공

- [ ] **Step 4: Commit**

```bash
git add Sources/MyWindowManager/UI/Editor/MoveView.swift Sources/MyWindowManager/UI/Editor/EditorWindow.swift
git commit -m "feat: grow/shrink hotkey settings UI in move tab"
```

---

### Task 7: SnapRestoreStore (TDD)

**Files:**
- Create: `Sources/MyWindowManager/Features/Snap/SnapRestoreStore.swift`
- Create: `Tests/MyWindowManagerTests/SnapRestoreStoreTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/MyWindowManagerTests/SnapRestoreStoreTests.swift` 생성:

```swift
import XCTest
@testable import MyWindowManager

@MainActor
final class SnapRestoreStoreTests: XCTestCase {
    func testRememberAndForget() {
        let store = SnapRestoreStore()
        let id: CGWindowID = 42
        XCTAssertNil(store.entry(for: id))

        store.remember(windowID: id,
                       preSnapSize: CGSize(width: 800, height: 600),
                       snappedFrame: CGRect(x: 0, y: 25, width: 960, height: 1055))
        let entry = store.entry(for: id)
        XCTAssertEqual(entry?.preSnapSize, CGSize(width: 800, height: 600))
        XCTAssertEqual(entry?.snappedFrame, CGRect(x: 0, y: 25, width: 960, height: 1055))

        store.forget(id)
        XCTAssertNil(store.entry(for: id))
    }

    func testReSnapOverwrites() {
        let store = SnapRestoreStore()
        store.remember(windowID: 1, preSnapSize: CGSize(width: 100, height: 100),
                       snappedFrame: .zero)
        store.remember(windowID: 1, preSnapSize: CGSize(width: 200, height: 200),
                       snappedFrame: .zero)
        XCTAssertEqual(store.entry(for: 1)?.preSnapSize, CGSize(width: 200, height: 200))
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter SnapRestoreStoreTests`
Expected: 컴파일 에러 — `cannot find 'SnapRestoreStore' in scope`

- [ ] **Step 3: 구현**

`Sources/MyWindowManager/Features/Snap/SnapRestoreStore.swift` 생성:

```swift
import Foundation
import CoreGraphics

/// 스냅된 창의 "스냅 직전 크기"를 기억해, 드래그로 떼어낼 때 복원할 수 있게
/// 한다. 인메모리 전용 — 앱 재시작이나 창이 닫히면 자연히 사라진다(무해).
@MainActor
final class SnapRestoreStore {
    struct Entry: Equatable {
        let preSnapSize: CGSize   // 스냅 직전 창 크기
        let snappedFrame: CGRect  // 스냅으로 적용한 프레임(AX 좌표)
    }

    private var entries: [CGWindowID: Entry] = [:]

    func remember(windowID: CGWindowID, preSnapSize: CGSize, snappedFrame: CGRect) {
        entries[windowID] = Entry(preSnapSize: preSnapSize, snappedFrame: snappedFrame)
    }

    func entry(for windowID: CGWindowID) -> Entry? {
        entries[windowID]
    }

    func forget(_ windowID: CGWindowID) {
        entries[windowID] = nil
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter SnapRestoreStoreTests`
Expected: 2 tests passed

- [ ] **Step 5: Commit**

```bash
git add Sources/MyWindowManager/Features/Snap/SnapRestoreStore.swift Tests/MyWindowManagerTests/SnapRestoreStoreTests.swift
git commit -m "feat: pre-snap size memory for unsnap restore"
```

---

### Task 8: ScreenHelper AX→Cocoa 변환 + SnapPreviewOverlay

**Files:**
- Modify: `Sources/MyWindowManager/Core/ScreenHelper.swift`
- Create: `Sources/MyWindowManager/Features/Snap/SnapPreviewOverlay.swift`

- [ ] **Step 1: ScreenHelper에 역변환 추가**

`Sources/MyWindowManager/Core/ScreenHelper.swift`의 `axFullFrame(of:)` 함수 아래에 추가:

```swift
    /// AX 좌표(좌상단 원점)의 rect를 Cocoa 좌표(좌하단 원점)로 되돌린다.
    /// `axVisibleFrame`의 역변환 — NSWindow/NSPanel 배치용.
    static func cocoaRect(fromAX rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        return CGRect(
            x: rect.minX,
            y: primary.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
```

- [ ] **Step 2: SnapPreviewOverlay 구현**

`Sources/MyWindowManager/Features/Snap/SnapPreviewOverlay.swift` 생성:

```swift
import AppKit

/// 드래그 중 스냅될 영역을 반투명 패널로 미리 보여준다.
/// 비활성(nonactivating)·클릭 통과라 드래그를 방해하지 않는다.
@MainActor
final class SnapPreviewOverlay {
    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.ignoresMouseEvents = true
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
        v.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        v.layer?.borderWidth = 2
        v.layer?.cornerRadius = 10
        p.contentView = v
        return p
    }()

    private var visible = false

    /// AX 좌표의 목표 프레임을 받아 표시한다. 이미 떠 있으면 부드럽게 이동.
    func show(axFrame: CGRect) {
        let target = ScreenHelper.cocoaRect(fromAX: axFrame)
        if visible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
            panel.orderFrontRegardless()
            visible = true
        }
    }

    func hide() {
        guard visible else { return }
        panel.orderOut(nil)
        visible = false
    }
}
```

- [ ] **Step 3: 빌드**

Run: `swift build`
Expected: 성공

- [ ] **Step 4: Commit**

```bash
git add Sources/MyWindowManager/Core/ScreenHelper.swift Sources/MyWindowManager/Features/Snap/SnapPreviewOverlay.swift
git commit -m "feat: snap preview overlay panel"
```

---

### Task 9: DragSnapMonitor (전역 드래그 감지 + 스냅 적용)

**Files:**
- Create: `Sources/MyWindowManager/Features/Snap/DragSnapMonitor.swift`

동작 요약(스펙 §1):
1. `leftMouseDown` → 세션 초기화, 커서 기록.
2. `leftMouseDragged` → 4px 이상 움직이면 mouseDown 지점에서 AX hit-test로 창을 1회 탐색. 이후 50ms 스로틀로 창 프레임을 폴링해 실제로 움직이면 "창 드래그"로 확정(텍스트 선택 오탐 배제).
3. 드래그 확정 후: (a) 복원 처리 — 스냅됐던 창이면 크기만 원복, (b) zone 판정 → 미리보기.
4. `leftMouseUp` → 최종 커서로 zone 재판정 후 스냅 적용 + 직전 크기 기억.

전역 모니터는 **자기 앱 이벤트를 받지 않는다** — 설정 창은 스냅 대상이 아님(의도). 핸들러는 메인 스레드 런루프에서 호출되므로 `HotkeyRegistry`와 같은 패턴으로 self 메서드를 직접 부른다.

- [ ] **Step 1: 구현**

`Sources/MyWindowManager/Features/Snap/DragSnapMonitor.swift` 생성:

```swift
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
```

- [ ] **Step 2: 빌드 + 테스트**

Run: `swift build && swift test`
Expected: 성공

- [ ] **Step 3: Commit**

```bash
git add Sources/MyWindowManager/Features/Snap/DragSnapMonitor.swift
git commit -m "feat: drag-to-edge snap monitor with preview and unsnap restore"
```

---

### Task 10: AppDelegate 와이어링

**Files:**
- Modify: `Sources/MyWindowManager/App/MyWindowManagerApp.swift`

- [ ] **Step 1: DragSnapMonitor 생성 + 구독**

`AppDelegate` 클래스(파일 하단)의 `private var cancellables = Set<AnyCancellable>()` 위에 프로퍼티 추가:

```swift
    private var snapMonitor: DragSnapMonitor?
```

`applicationDidFinishLaunching(_:)` 안, `store.objectWillChange` 구독 블록 **다음**에 추가:

```swift
        // 드래그 스냅 — 설정과 접근성 권한 변화에 맞춰 시작/중지.
        snapMonitor = DragSnapMonitor(settings: store.snapSettings)
        store.$snapSettings
            .combineLatest(ax.$isTrusted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings, trusted in
                self?.snapMonitor?.update(settings: settings, axTrusted: trusted)
            }
            .store(in: &cancellables)
```

(`store.$snapSettings`와 `ax.$isTrusted`는 구독 즉시 현재 값을 방출하므로 초기 시작도 이 구독이 처리한다.)

- [ ] **Step 2: 빌드**

Run: `swift build`
Expected: 성공

- [ ] **Step 3: Commit**

```bash
git add Sources/MyWindowManager/App/MyWindowManagerApp.swift
git commit -m "feat: wire drag snap monitor to settings and AX permission"
```

---

### Task 11: "스냅" 설정 탭 신설

**Files:**
- Create: `Sources/MyWindowManager/UI/Editor/SnapView.swift`
- Modify: `Sources/MyWindowManager/UI/Editor/EditorWindow.swift`

- [ ] **Step 1: SnapView 생성**

`Sources/MyWindowManager/UI/Editor/SnapView.swift` 생성:

```swift
import SwiftUI

/// "스냅" 탭 — 드래그 스냅의 항목별 on/off 설정.
struct SnapView: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        Form {
            Section {
                Toggle("드래그 스냅 사용", isOn: binding(\.enabled))
            } footer: {
                Text("창을 드래그해 화면 가장자리에 가져가면 자동으로 리사이즈됩니다. macOS 자체 창 타일링과 겹치면 미리보기가 이중으로 표시될 수 있으니, 시스템 설정 > 데스크탑 및 Dock > 창 타일링을 끄는 것을 권장합니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section("가장자리") {
                Toggle("왼쪽 — 왼쪽 절반", isOn: binding(\.edgeLeft))
                Toggle("오른쪽 — 오른쪽 절반", isOn: binding(\.edgeRight))
                Toggle("위 — 최대화", isOn: binding(\.edgeTop))
                Toggle("아래 — 아래 절반", isOn: binding(\.edgeBottom))
            }
            .disabled(!store.snapSettings.enabled)
            Section("부가 동작") {
                Toggle("모서리 쿼터 스냅", isOn: binding(\.corners))
                Toggle("미리보기 오버레이", isOn: binding(\.preview))
                Toggle("스냅 해제 시 크기 복원", isOn: binding(\.restoreOnUnsnap))
            }
            .disabled(!store.snapSettings.enabled)
        }
        .formStyle(.grouped)
    }

    private func binding(_ kp: WritableKeyPath<SnapSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.snapSettings[keyPath: kp] },
            set: { store.snapSettings[keyPath: kp] = $0 }
        )
    }
}
```

- [ ] **Step 2: EditorTab에 케이스 추가**

`Sources/MyWindowManager/UI/Editor/EditorWindow.swift`에서 다섯 곳 수정:

케이스 선언 (`move` 다음에 `snap`):

```swift
    case presets, cycles, layouts, displays, move, snap, general, info
```

`label`의 `case .move` 아래에:

```swift
        case .snap: return "스냅"
```

`symbol`의 `case .move` 아래에:

```swift
        case .snap: return "rectangle.lefthalf.filled"
```

`tint`의 `case .move` 아래에:

```swift
        case .snap: return .pink
```

`hasTranslucentDetail`의 불투명 케이스 목록에 `.snap` 추가:

```swift
        case .presets, .cycles, .layouts, .displays, .move, .snap, .general: return false
```

`EditorRootView.detailView`의 `case .move: MoveView()` 아래에:

```swift
        case .snap: SnapView()
```

- [ ] **Step 3: 빌드 + 테스트**

Run: `swift build && swift test`
Expected: 성공

- [ ] **Step 4: Commit**

```bash
git add Sources/MyWindowManager/UI/Editor/SnapView.swift Sources/MyWindowManager/UI/Editor/EditorWindow.swift
git commit -m "feat: snap settings tab with per-item toggles"
```

---

### Task 12: 스모크 테스트 문서 + 최종 검증 + 앱 재시작

**Files:**
- Modify: `docs/smoke-test.md`

- [ ] **Step 1: 스모크 테스트 시나리오 추가**

`docs/smoke-test.md` 끝에 추가:

```markdown
## 드래그 스냅

전제: 설정 > 스냅에서 모든 토글 켬. macOS 시스템 창 타일링(시스템 설정 >
데스크탑 및 Dock)은 꺼두는 것을 권장(미리보기 이중 표시 방지).

- [ ] 창을 왼쪽 가장자리로 드래그 → 미리보기 표시 → 놓으면 왼쪽 절반
- [ ] 오른쪽 가장자리 → 오른쪽 절반
- [ ] 위 가장자리 → 최대화
- [ ] 아래 가장자리 → 아래 절반
- [ ] 네 모서리 → 각 쿼터
- [ ] 스냅된 창을 드래그로 떼어냄 → 원래 크기로 복원
- [ ] 텍스트 드래그(선택)를 화면 가장자리에서 해도 스냅되지 않음
- [ ] 설정에서 "위 — 최대화" 끄면 위 가장자리에서 미리보기/스냅 없음
- [ ] "미리보기 오버레이" 끄면 미리보기 없이 스냅만 동작
- [ ] 마스터 토글 끄면 아무 동작 없음, 다시 켜면 재동작(앱 재시작 불필요)
- [ ] (멀티 디스플레이) 다른 디스플레이 가장자리에서도 동작

## 창 확대/축소

전제: 설정 > 이동·크기 > 창 크기에서 확대/축소 핫키 등록.

- [ ] 확대 핫키 → 창이 중심을 유지하며 커짐(기본 10%)
- [ ] 축소 핫키 → 중심 유지하며 작아짐, 여러 번 눌러도 최소 크기에서 멈춤
- [ ] 화면 가장자리 근처에서 확대 → 화면 안쪽으로 밀려 들어옴, 화면보다 커지지 않음
- [ ] 비율을 20%로 바꾸면 증감 폭이 커짐
- [ ] 기존 config.json 사용자: 업데이트 후 프리셋/사이클/레이아웃/이동 핫키 유지
```

- [ ] **Step 2: 전체 테스트 + 빌드**

Run: `swift test && swift build`
Expected: 전체 통과

- [ ] **Step 3: 앱 재빌드 + 재실행** (프로젝트 규칙 — 코드 변경 후 자동 재실행)

```bash
pkill -x MyWindowManager 2>/dev/null || true
make run
```

Expected: `dist/My Window Manager.app` 실행됨. 메뉴바 아이콘 표시.

- [ ] **Step 4: Commit**

```bash
git add docs/smoke-test.md
git commit -m "docs: smoke test scenarios for drag snap and window sizing"
```

---

## 스펙 커버리지 체크리스트 (self-review용)

| 스펙 요구사항 | 태스크 |
|---|---|
| 엣지 4방향 스냅 (좌우 반쪽, 상 최대화, 하 아래 반쪽) | 3, 9 |
| 코너 쿼터 스냅, 코너 우선, off 시 최근접 엣지 폴백 | 3 |
| threshold 8px / 코너 128px / 드래그 4px / 해제 10px | 3, 9 |
| 미리보기 오버레이 (비활성·클릭 통과) | 8, 9 |
| 스냅 해제 시 크기 복원 (CGWindowID, 수동 리사이즈 시 무효) | 7, 9 |
| 항목별 on/off 설정 + 마스터 off 시 모니터 중지 | 2, 9, 10, 11 |
| 접근성 권한 연동 | 10 |
| 자기 앱 창 제외 (전역 모니터 특성) | 9 |
| 확대/축소: 중심 앵커, 화면 N%, 클램프, 최소 크기 | 1 |
| SizeBinding 핫키 + resetCycleState | 5 |
| 스텝 비율 설정(2~30%, 기본 10%) | 4, 6 |
| config 하위호환(v3, decodeIfPresent) + export/import | 4 |
| hotkeyConflicts에 size 반영 | 4 |
| 설정 UI: 스냅 탭 신설 + 이동·크기 탭 | 6, 11 |
| 시스템 타일링 안내 문구 | 11, 12 |
| 테스트 타깃 + 순수 함수 테스트 + 스모크 시나리오 | 1, 2, 3, 4, 7, 12 |
