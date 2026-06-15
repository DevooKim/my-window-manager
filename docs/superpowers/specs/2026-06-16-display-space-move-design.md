# 디스플레이/스페이스 창 이동 기능 설계

작성일: 2026-06-16

## 개요

포커스된 창을 인접한 **디스플레이(모니터)** 또는 **스페이스(Mission Control 데스크톱)**로 옮기는
4개의 고정 이동 액션을 추가한다. 기존 리사이즈 프리셋과는 별개의 독립 기능이다.

- 다음 디스플레이로 이동 / 이전 디스플레이로 이동
- 다음 스페이스로 이동 / 이전 스페이스로 이동

각 액션에 글로벌 핫키를 바인딩할 수 있고, 메뉴바와 새 "이동" 설정 탭에 노출된다.

## 데이터 모델

`MoveAction` enum과 핫키 바인딩 `MoveBinding`을 추가한다.

```swift
enum MoveAction: String, Codable, CaseIterable {
    case displayNext, displayPrev, spaceNext, spacePrev
}

struct MoveBinding: Codable, Hashable {
    var action: MoveAction
    var hotkey: HotkeyConfig?
}
```

- `AppConfig`에 `moveBindings: [MoveBinding]` 필드 추가, `version`을 2로 올림.
- 기존 config는 `decodeIfPresent`로 빈 배열 기본값 처리(마이그레이션). 다른 신규 필드와 동일한 패턴.
- 핫키 충돌 검사(`ConfigStore.hotkeyConflicts(for:excludingId:)`)에 `moveBindings`도 포함.
- 기본값: 모든 바인딩 핫키 없음(nil). 사용자가 직접 지정. StarterPresets는 건드리지 않음.

## 액션 실행 로직

### 디스플레이 이동 — `DisplayMover` (공개 API만)

1. `WindowController.focusedWindow()`로 포커스 창 획득(기존 `ResizeApplier`와 동일).
2. 창이 현재 있는 `NSScreen`을 `ScreenHelper.screen(containing:)`로 찾고, `NSScreen.screens`에서
   다음/이전 인덱스 계산(순환: 마지막 → 처음).
3. 현재 창 프레임을 **현재 화면 기준 상대 비율로 환산**한 뒤, 대상 디스플레이의 placement area에
   동일 비율로 재배치. 해상도가 다른 모니터 간 이동에서도 창이 화면 밖으로 나가지 않게 한다.
4. 디스플레이가 1개뿐이면 no-op(조용히 무시).

### 스페이스 이동 — `SpaceMover` (비공개 CGS API)

1. 포커스 창의 `CGWindowID` 획득(`_AXUIElementGetWindow`).
2. `CGSMainConnectionID()` → `CGSCopySpaces`로 현재 디스플레이의 스페이스 목록 +
   `CGSGetActiveSpace`로 현재 스페이스 → 다음/이전 스페이스 ID 계산.
3. `CGSMoveWindowsToManagedSpace(cid, [windowID], targetSpace)`로 창 이동.
4. **화면도 그 스페이스로 전환** — `CGEvent`로 macOS 기본 단축키 `⌃→`/`⌃←`(다음/이전 스페이스) 합성.
   방향은 창 이동과 일관(다음이면 창 이동 후 `⌃→`). `CGSManagedDisplaySetCurrentSpace` 직접 호출은
   Dock 상태가 틀어져 글리치가 생기므로 사용하지 않는다.
5. 스페이스가 1개뿐이면 no-op.

### 비공개 API 격리 — `CGSPrivate.swift`

- 모든 CGS/SkyLight 심볼은 런타임 `dlsym`으로 로드. 심볼이 없으면(OS 업데이트로 제거 시)
  조용히 no-op + 1회 경고 로그.
- CGS 관련 코드는 `CGSPrivate.swift` 한 파일로 격리.

## UI · 트리거

### 새 "이동" 탭 — `MoveView`

- `EditorTab`에 `.move` 케이스 추가. 사이드바 아이콘 `arrow.left.arrow.right`, 틴트 색 지정.
- 4개 액션을 행으로 표시: "다음 디스플레이로", "이전 디스플레이로", "다음 스페이스로", "이전 스페이스로".
- 각 행에 `HotkeyCaptureView`(기존 재사용)로 핫키 캡처/표시 + 충돌 경고.
- 스페이스 행 하단 안내: "스페이스 이동은 비공개 기능을 사용하며, 화면 전환은 시스템 설정의
  Mission Control 단축키(⌃←/⌃→)가 켜져 있어야 동작합니다."

### 메뉴바 — `MenuBarContent`

- 기존 Resize/Layouts/Cycles 섹션과 동일 패턴으로 "이동" 섹션 추가. 4개 버튼 + 핫키 표시.
- 클릭 시 해당 mover 직접 호출.

### 핫키 — `HotkeyRegistry.rebuild()`

- presets/cycles/layouts 등록 옆에 `moveBindings` 등록 추가.
- 핸들러는 액션에 따라 `DisplayMover`/`SpaceMover` 호출. cycle 상태 리셋도 동일하게.

## 에러 처리

- 포커스 창 없음 → no-op
- 디스플레이 1개 → no-op
- CGS 심볼 로드 실패 → no-op + 1회 경고 로그
- 스페이스 1개 → no-op

## 테스트

- `MoveAction`/`MoveBinding` Codable 라운드트립, config v1→v2 마이그레이션(필드 없는 기존 json 디코딩).
- 디스플레이 인덱스 순환 계산(다음/이전, 경계 wrap).
- 핫키 충돌 검사에 `moveBindings` 포함 여부.
- CGS·NSScreen 실제 동작은 수동 검증(단위 테스트 어려움).

## 비범위 (YAGNI)

- 절대 디스플레이/스페이스 지정(특정 모니터·번호) — 상대 이동만.
- 리사이즈 프리셋과의 결합(이동 후 리사이즈) — 독립 액션만.
- SIP 비활성화가 필요한 yabai식 완전 제어.
