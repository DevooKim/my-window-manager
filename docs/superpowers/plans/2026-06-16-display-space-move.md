# 디스플레이/스페이스 창 이동 기능 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 포커스된 창을 인접한 디스플레이/스페이스로 옮기는 4개의 핫키 바인딩 가능한 독립 액션을 추가한다.

**Architecture:** `MoveAction`(4-case enum)과 `MoveBinding`을 `AppConfig`에 추가하고, 디스플레이 이동은 공개 NSScreen API(`DisplayMover`), 스페이스 이동은 비공개 CGS API(`SpaceMover` + `CGSPrivate.swift`, dlsym 격리)로 구현한다. 새 "이동" 설정 탭(`MoveView`)과 메뉴바 섹션에서 트리거하며, `HotkeyRegistry`가 핫키를 등록한다.

**Tech Stack:** Swift 5.9, SwiftPM executable target, AppKit/ApplicationServices, SkyLight 비공개 CGS API(dlsym), HotKey 라이브러리.

> **테스트 정책:** 이 프로젝트는 executable 타깃이며 테스트 인프라가 없다(빈 `Tests/`, 기존 테스트 0개). 검증은 **`make app` 빌드 성공 + 수동 런타임 확인**으로 한다. 각 태스크는 빌드 통과를 검증 기준으로 삼고, 런타임 동작은 마지막에 일괄 수동 검증한다.

---

## File Structure

- Create: `Sources/MyWindowManager/Models/MoveAction.swift` — `MoveAction` enum + `MoveBinding` struct + 표시 레이블.
- Create: `Sources/MyWindowManager/Features/Move/DisplayMover.swift` — 포커스 창을 다음/이전 디스플레이로 이동.
- Create: `Sources/MyWindowManager/Features/Move/SpaceMover.swift` — 포커스 창을 다음/이전 스페이스로 이동 + 화면 전환.
- Create: `Sources/MyWindowManager/Core/CGSPrivate.swift` — 비공개 CGS/SkyLight 심볼을 dlsym으로 안전 로드.
- Modify: `Sources/MyWindowManager/Storage/ConfigStore.swift` — `AppConfig.moveBindings`, 마이그레이션, 충돌검사.
- Modify: `Sources/MyWindowManager/Hotkey/HotkeyRegistry.swift` — moveBindings 등록.
- Create: `Sources/MyWindowManager/UI/Editor/MoveView.swift` — "이동" 설정 탭.
- Modify: `Sources/MyWindowManager/UI/Editor/EditorWindow.swift` — `EditorTab.move` 케이스 + detail 라우팅.
- Modify: `Sources/MyWindowManager/UI/MenuBar/MenuBarContent.swift` — "이동" 메뉴 섹션.

---

## Task 1: MoveAction / MoveBinding 모델

**Files:**
- Create: `Sources/MyWindowManager/Models/MoveAction.swift`

- [ ] **Step 1: 모델 파일 작성**

```swift
import Foundation

/// 포커스된 창을 인접한 디스플레이/스페이스로 옮기는 고정 액션.
enum MoveAction: String, Codable, CaseIterable, Identifiable {
    case displayNext
    case displayPrev
    case spaceNext
    case spacePrev

    var id: String { rawValue }

    /// UI·메뉴에 표시할 이름.
    var label: String {
        switch self {
        case .displayNext: return "다음 디스플레이로"
        case .displayPrev: return "이전 디스플레이로"
        case .spaceNext:   return "다음 스페이스로"
        case .spacePrev:   return "이전 스페이스로"
        }
    }

    var isSpace: Bool { self == .spaceNext || self == .spacePrev }

    /// +1 = 다음, -1 = 이전.
    var direction: Int { (self == .displayNext || self == .spaceNext) ? 1 : -1 }
}

/// 한 이동 액션과 그에 바인딩된(선택적) 핫키.
struct MoveBinding: Codable, Hashable, Identifiable {
    var action: MoveAction
    var hotkey: HotkeyConfig?

    var id: String { action.rawValue }
}
```

- [ ] **Step 2: 빌드 검증**

Run: `make app 2>&1 | tail -4`
Expected: `Build complete!`

- [ ] **Step 3: 커밋**

```bash
git add Sources/MyWindowManager/Models/MoveAction.swift
git commit -m "feat: add MoveAction and MoveBinding models"
```

---

## Task 2: ConfigStore에 moveBindings 추가 + 마이그레이션

**Files:**
- Modify: `Sources/MyWindowManager/Storage/ConfigStore.swift`

- [ ] **Step 1: AppConfig에 필드 추가 (version 2, moveBindings)**

`AppConfig` 정의(라인 5~34)를 아래로 교체:

```swift
struct AppConfig: Codable {
    var version: Int = 2
    var presets: [ResizePreset]
    var layouts: [Layout]
    var cycles: [PresetCycle]
    var deadzones: [DisplayDeadzone]
    var cycleHUDStyle: CycleHUDStyle
    var moveBindings: [MoveBinding]

    init(presets: [ResizePreset], layouts: [Layout], cycles: [PresetCycle],
         deadzones: [DisplayDeadzone], cycleHUDStyle: CycleHUDStyle = .thumbnails,
         moveBindings: [MoveBinding] = []) {
        self.presets = presets
        self.layouts = layouts
        self.cycles = cycles
        self.deadzones = deadzones
        self.cycleHUDStyle = cycleHUDStyle
        self.moveBindings = moveBindings
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
    }
}
```

- [ ] **Step 2: @Published 프로퍼티 추가**

`ConfigStore`에서 `@Published var cycleHUDStyle ...` 블록(라인 44~46) 바로 아래에 추가:

```swift
    @Published var moveBindings: [MoveBinding] = [] {
        didSet { if moveBindings != oldValue { save() } }
    }
```

- [ ] **Step 3: load()에 반영**

`load()` 내부 성공 분기에서 `self.cycleHUDStyle = cfg.cycleHUDStyle` 다음 줄에 추가:

```swift
            self.moveBindings = cfg.moveBindings
```

같은 메서드의 else(첫 실행) 분기에서 `self.deadzones = []` 다음 줄에 추가:

```swift
            self.moveBindings = []
```

- [ ] **Step 4: save()/export()/importConfig()에 반영**

`save()`의 `AppConfig(...)` 생성(라인 112)을 교체:

```swift
        let cfg = AppConfig(presets: presets, layouts: layouts, cycles: cycles, deadzones: deadzones, cycleHUDStyle: cycleHUDStyle, moveBindings: moveBindings)
```

`export(to:)`의 `AppConfig(...)` 생성(라인 137)도 동일하게 교체(같은 인자):

```swift
        let cfg = AppConfig(presets: presets, layouts: layouts, cycles: cycles, deadzones: deadzones, cycleHUDStyle: cycleHUDStyle, moveBindings: moveBindings)
```

`importConfig(from:)`에서 `cycleHUDStyle = cfg.cycleHUDStyle` 다음 줄에 추가:

```swift
        moveBindings = cfg.moveBindings
```

- [ ] **Step 5: 핫키 충돌 검사에 moveBindings 포함**

`hotkeyConflicts(for:excludingId:)`의 layouts 루프(라인 272~274) 다음, `return result` 앞에 추가:

```swift
        for b in moveBindings where matches(b.hotkey) {
            result.append("\(b.action.label) (이동)")
        }
```

- [ ] **Step 6: 빌드 검증**

Run: `make app 2>&1 | tail -4`
Expected: `Build complete!`

- [ ] **Step 7: 커밋**

```bash
git add Sources/MyWindowManager/Storage/ConfigStore.swift
git commit -m "feat: persist moveBindings in config (v2 migration)"
```

---

## Task 3: DisplayMover (공개 API)

**Files:**
- Create: `Sources/MyWindowManager/Features/Move/DisplayMover.swift`

- [ ] **Step 1: DisplayMover 작성**

창의 현재 프레임을 현재 화면 placement area 기준 상대 비율로 환산한 뒤, 대상 화면의 placement area에 같은 비율로 재배치한다. 해상도가 달라도 화면 밖으로 나가지 않는다.

```swift
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
```

- [ ] **Step 2: 빌드 검증**

Run: `make app 2>&1 | tail -4`
Expected: `Build complete!`

- [ ] **Step 3: 커밋**

```bash
git add Sources/MyWindowManager/Features/Move/DisplayMover.swift
git commit -m "feat: DisplayMover — move focused window to adjacent display"
```

---

## Task 4: CGSPrivate — 비공개 CGS 심볼 dlsym 로딩

**Files:**
- Create: `Sources/MyWindowManager/Core/CGSPrivate.swift`

> SkyLight.framework의 비공개 CGS 함수들을 `dlsym`으로 런타임 로드한다. 심볼이 없으면 `nil`이 되어 호출부가 no-op + 1회 경고한다. C 함수 포인터를 Swift 클로저 타입으로 캐스팅한다.

- [ ] **Step 1: CGSPrivate 작성**

```swift
import Foundation
import CoreGraphics

/// 비공개 CGS/SkyLight 심볼을 런타임 dlsym으로 로드한다. OS 업데이트로 심볼이
/// 사라지면 각 프로퍼티가 nil이 되고, 호출부는 조용히 no-op 처리한다.
/// (스페이스 이동에 공개 API가 없어 불가피하게 사용 — design 문서 참조.)
enum CGSPrivate {
    typealias ConnID = UInt32   // CGSConnectionID
    typealias SpaceID = UInt64  // CGSSpaceID

    // SkyLight.framework 핸들 (CoreGraphics가 재노출). 전역에서 dlsym.
    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

    private static func sym(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(handle, name) ?? dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) // RTLD_DEFAULT
    }

    // CGSConnectionID CGSMainConnectionID(void)
    typealias MainConnectionFn = @convention(c) () -> ConnID
    static let mainConnectionID: MainConnectionFn? =
        sym("CGSMainConnectionID").map { unsafeBitCast($0, to: MainConnectionFn.self) }

    // CGSSpaceID CGSGetActiveSpace(CGSConnectionID)
    typealias GetActiveSpaceFn = @convention(c) (ConnID) -> SpaceID
    static let getActiveSpace: GetActiveSpaceFn? =
        sym("CGSGetActiveSpace").map { unsafeBitCast($0, to: GetActiveSpaceFn.self) }

    // CFArrayRef CGSCopySpaces(CGSConnectionID, int mask)
    // mask 7 = all spaces (current + others) for the connection.
    typealias CopySpacesFn = @convention(c) (ConnID, Int32) -> Unmanaged<CFArray>?
    static let copySpaces: CopySpacesFn? =
        sym("CGSCopySpaces").map { unsafeBitCast($0, to: CopySpacesFn.self) }

    // void CGSMoveWindowsToManagedSpace(CGSConnectionID, CFArrayRef windows, CGSSpaceID)
    typealias MoveWindowsFn = @convention(c) (ConnID, CFArray, SpaceID) -> Void
    static let moveWindowsToManagedSpace: MoveWindowsFn? =
        sym("CGSMoveWindowsToManagedSpace").map { unsafeBitCast($0, to: MoveWindowsFn.self) }

    static var isAvailable: Bool {
        mainConnectionID != nil && getActiveSpace != nil
            && copySpaces != nil && moveWindowsToManagedSpace != nil
    }
}

/// 비공개 _AXUIElementGetWindow — AXUIElement → CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError
```

- [ ] **Step 2: 빌드 검증 (AXUIElement import 확인)**

`_AXUIElementGetWindow` 시그니처에 `AXUIElement`/`AXError`가 필요하므로 파일 상단 import에 `import ApplicationServices`를 추가해야 한다. Step 1의 import를 다음으로 교체:

```swift
import Foundation
import CoreGraphics
import ApplicationServices
```

Run: `make app 2>&1 | tail -6`
Expected: `Build complete!` (실패 시 `@_silgen_name` 충돌이면 — 다른 파일에 이미 선언됐는지 `grep -rn "_AXUIElementGetWindow" Sources` 로 확인하고 중복 제거)

- [ ] **Step 3: 커밋**

```bash
git add Sources/MyWindowManager/Core/CGSPrivate.swift
git commit -m "feat: CGSPrivate — dlsym-loaded private CGS symbols for space ops"
```

---

## Task 5: SpaceMover (비공개 CGS API + 화면 전환)

**Files:**
- Create: `Sources/MyWindowManager/Features/Move/SpaceMover.swift`

- [ ] **Step 1: SpaceMover 작성**

창을 인접 스페이스로 옮기고, macOS 기본 단축키(⌃→/⌃←)를 합성해 화면도 그 스페이스로 전환한다.

```swift
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
```

- [ ] **Step 2: 빌드 검증**

Run: `make app 2>&1 | tail -6`
Expected: `Build complete!`

- [ ] **Step 3: 커밋**

```bash
git add Sources/MyWindowManager/Features/Move/SpaceMover.swift
git commit -m "feat: SpaceMover — move window to adjacent space + follow"
```

---

## Task 6: HotkeyRegistry에 moveBindings 등록

**Files:**
- Modify: `Sources/MyWindowManager/Hotkey/HotkeyRegistry.swift`

- [ ] **Step 1: Target에 move 케이스 추가**

`enum Target`(라인 7~11)을 교체:

```swift
    enum Target {
        case preset(UUID)
        case layout(UUID)
        case cycle(UUID)
        case move(MoveAction)
    }
```

- [ ] **Step 2: rebuild()에 등록 루프 추가**

`rebuild()`의 cycles 루프(라인 71~79) 다음, 메서드 닫는 괄호 앞에 추가:

```swift
        for binding in store.moveBindings {
            guard let cfg = binding.hotkey, let hk = cfg.hotKey else { continue }
            let key = HotKey(key: hk.key, modifiers: hk.mods)
            let action = binding.action
            key.keyDownHandler = { [weak self] in
                self?.resetCycleState()
                if action.isSpace {
                    SpaceMover.move(direction: action.direction)
                } else {
                    DisplayMover.move(direction: action.direction)
                }
            }
            hotkeys.append((.move(action), key))
        }
```

- [ ] **Step 3: 빌드 검증**

Run: `make app 2>&1 | tail -4`
Expected: `Build complete!`

- [ ] **Step 4: 커밋**

```bash
git add Sources/MyWindowManager/Hotkey/HotkeyRegistry.swift
git commit -m "feat: register move-action hotkeys"
```

---

## Task 7: "이동" 설정 탭 (MoveView + EditorTab)

**Files:**
- Modify: `Sources/MyWindowManager/UI/Editor/EditorWindow.swift`
- Create: `Sources/MyWindowManager/UI/Editor/MoveView.swift`

- [ ] **Step 1: EditorTab에 .move 추가**

`EditorWindow.swift`에서 `enum EditorTab`의 `case presets, cycles, layouts, displays, general, info` 줄을 교체:

```swift
    case presets, cycles, layouts, displays, move, general, info
```

`label` switch에 추가(`case .general:` 앞):

```swift
        case .move: return "이동"
```

`symbol` switch에 추가(`case .general:` 앞):

```swift
        case .move: return "arrow.left.arrow.right"
```

`tint` switch에 추가(`case .general:` 앞):

```swift
        case .move: return .orange
```

`hasTranslucentDetail`의 `.presets, .cycles, .layouts, .displays, .general` 케이스 줄에 `.move` 포함되도록 교체:

```swift
        case .presets, .cycles, .layouts, .displays, .move, .general: return false
```

`detailView` switch(`EditorRootView` 내부)에 추가(`case .general:` 앞):

```swift
        case .move: MoveView()
```

- [ ] **Step 2: MoveView 작성**

```swift
import SwiftUI

/// "이동" 탭 — 포커스 창을 인접 디스플레이/스페이스로 옮기는 액션의 핫키 설정.
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
}
```

> 참고: `HotkeyConflictWarning`의 `selfId`는 `UUID?` 타입이라 move 바인딩에는 `nil`을 넘긴다. 이동 액션끼리는 id가 UUID가 아니므로 자기 자신이 충돌 목록에 "(이동)"으로 뜰 수 있는데, `hotkeyConflicts`는 `matches(b.hotkey)`만 보고 같은 action을 제외하지 않는다. 이를 막기 위해 다음 스텝에서 충돌검사를 보정한다.

- [ ] **Step 3: 자기 자신 제외 — ConfigStore.hotkeyConflicts 보정**

`Sources/MyWindowManager/Storage/ConfigStore.swift`의 moveBindings 충돌 루프(Task 2 Step 5에서 추가한 것)를, 동일한 핫키를 가진 "다른" 바인딩만 잡도록 교체한다. `hotkeyConflicts`는 `HotkeyConfig`만 받으므로, 같은 combo를 가진 move 바인딩이 2개 이상일 때만 충돌로 표시:

```swift
        let movesWithSame = moveBindings.filter { matches($0.hotkey) }
        if movesWithSame.count > 1 {
            for b in movesWithSame {
                result.append("\(b.action.label) (이동)")
            }
        }
```

(기존 단순 루프를 위 블록으로 대체. 한 액션에만 배정된 핫키는 자기 자신과 충돌하지 않음.)

- [ ] **Step 4: 빌드 검증**

Run: `make app 2>&1 | tail -6`
Expected: `Build complete!`

- [ ] **Step 5: 커밋**

```bash
git add Sources/MyWindowManager/UI/Editor/EditorWindow.swift Sources/MyWindowManager/UI/Editor/MoveView.swift Sources/MyWindowManager/Storage/ConfigStore.swift
git commit -m "feat: 이동 settings tab with per-action hotkey config"
```

---

## Task 8: 메뉴바 "이동" 섹션

**Files:**
- Modify: `Sources/MyWindowManager/UI/MenuBar/MenuBarContent.swift`

- [ ] **Step 1: "이동" 섹션 추가**

"Resize Presets" Section 블록(라인 58~64) 다음, 그 아래 `Divider()` 앞에 추가:

```swift
            let moves = store.moveBindings.filter { $0.hotkey != nil }
            if !moves.isEmpty {
                Divider()
                Section("이동") {
                    ForEach(moves) { binding in
                        Button(menuTitle(binding.action.label, hotkey: binding.hotkey)) {
                            if binding.action.isSpace {
                                SpaceMover.move(direction: binding.action.direction)
                            } else {
                                DisplayMover.move(direction: binding.action.direction)
                            }
                        }
                    }
                }
            }
```

- [ ] **Step 2: 빌드 검증**

Run: `make app 2>&1 | tail -4`
Expected: `Build complete!`

- [ ] **Step 3: 커밋**

```bash
git add Sources/MyWindowManager/UI/MenuBar/MenuBarContent.swift
git commit -m "feat: move actions in menu bar"
```

---

## Task 9: 수동 런타임 검증

**Files:** (없음 — 실행 확인만)

- [ ] **Step 1: 빌드 + 재실행**

```bash
osascript -e 'quit app "My Window Manager"' 2>/dev/null; pkill -f "My Window Manager.app" 2>/dev/null; make app 2>&1 | tail -3 && open "dist/My Window Manager.app"
```

- [ ] **Step 2: 설정 "이동" 탭 확인**

메뉴바 → 설정 → "이동" 탭. 4개 액션 행과 각 핫키 캡처 버튼, 스페이스 안내 문구가 보이는지 확인. 각 액션에 핫키를 배정(예: 디스플레이 ⌃⌥→/←, 스페이스 ⌃⌥⇧→/←).

- [ ] **Step 3: 디스플레이 이동 동작 (모니터 2개 이상 필요)**

창 하나 포커스 → "다음 디스플레이로" 핫키 → 창이 옆 모니터로 같은 상대 위치/크기로 이동하는지. 모니터 1개면 no-op(아무 일 없음)인지.

- [ ] **Step 4: 스페이스 이동 동작 (스페이스 2개 이상 필요)**

시스템 설정 > 키보드 > 단축키 > Mission Control 에서 "한 스페이스 왼쪽/오른쪽으로 이동"이 켜져 있는지 확인. 창 포커스 → "다음 스페이스로" 핫키 → 창이 옆 스페이스로 이동하고 화면도 따라 전환되는지.

- [ ] **Step 5: 마이그레이션 확인**

기존 config.json이 정상 로드되고(기존 프리셋/사이클 유지), 새 moveBindings가 추가·저장되는지. `~/Library/Application Support/MyWindowManager/config.json` 에 `moveBindings`, `"version" : 2` 가 있는지:

```bash
grep -E '"version"|moveBindings' ~/Library/Application\ Support/MyWindowManager/config.json
```

- [ ] **Step 6: 메뉴바 확인**

핫키가 배정된 이동 액션이 메뉴바에 "이동" 섹션으로 뜨고, 클릭 시 동작하는지.

---

## 베타 릴리스 (검증 통과 후)

- [ ] main에 머지: `git checkout main && git merge --no-ff feat/display-space-move`
- [ ] patch 범프: `make bump-patch`
- [ ] 베타 발행: `make publish` (베타 표기 방식은 publish 스크립트 확인 후 결정 — prerelease 플래그 지원 여부에 따라 `gh release ... --prerelease` 사용)
