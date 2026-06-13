# 사이드바 설정 UI 전면 개편 — 설계 문서

- **날짜**: 2026-06-13
- **대상**: 설정/편집 창 셸 (`EditorRootView`, `EditorTab`, `AppState.openEditor`)
- **참조**: BetterDisplay 설정 창 (NavigationSplitView 사이드바 + 디테일)

## 목표

상단 탭바(`TabView`)로 된 설정 창을 BetterDisplay 스타일의 **사이드바 + 디테일**(`NavigationSplitView`) 레이아웃으로 전면 개편한다. 각 항목의 **편집 화면 로직·바인딩은 그대로 두고**, 창 셸과 사이드바 표현만 교체한다.

## 핵심 결정 (사용자 승인됨)

1. **사이드바 구성 = 평면 6항목** (섹션 그룹 없음): 프리셋 · 사이클 · 레이아웃 · 디스플레이 · 일반 · 정보.
2. **창 크기 = 고정 기본 크기 + 사용자 리사이즈 + 크기 기억** (macOS 설정 앱 / BetterDisplay 방식). 항목 전환 시 창이 리사이즈되지 않는다.
3. **비주얼: 컬러 SF Symbol 아이콘 + 일체형 타이틀바 / 사이드바 글래스.** 그룹 카드(.grouped Form)나 설정별 설명문 추가는 이번 범위에서 제외.

## 범위 밖 (이번 작업에서 하지 않음)

- 각 편집 화면(`PresetEditorView`, `CycleEditorView`, `LayoutEditorView`, `DisplayDeadzoneView`, `GeneralView`, `InfoView`) 내부 구조·로직·문구 변경.
- 설정별 회색 설명문 신규 작성.
- 그룹 카드 스타일 도입.
- 배포 타겟 변경 (`Package.swift`는 현재 `.macOS(.v14)` 유지).

## 설계

### 1. 구조 — NavigationSplitView

`EditorRootView`의 `TabView`를 `NavigationSplitView`로 교체한다.

- **사이드바**: `List(selection:)` 기반 평면 6항목. 각 행 = 컬러 SF Symbol 아이콘 + 라벨.
- **디테일**: 선택된 `EditorTab`에 따라 기존 뷰를 `switch`로 그대로 렌더링. 내부 바인딩·로직 무변경.
- 선택 상태는 `AppState`가 소유하는 `@Published var selectedTab: EditorTab`에 바인딩한다 (이유는 §3 참조). `EditorRootView`는 이 바인딩을 받아 사용한다.
- 사이드바 너비: `minWidth ~200`, `idealWidth ~220`.

### 2. 컬러 아이콘

`EditorTab`에 `symbol: String`, `tint: Color`를 추가한다. 사이드바 행은 `Label(label, systemImage: symbol)`에 아이콘 틴트를 적용해 렌더링한다.

| 항목 | symbol | tint |
|---|---|---|
| 프리셋 (presets) | `rectangle.split.2x1` | `.blue` |
| 사이클 (cycles) | `arrow.triangle.2.circlepath` | `.purple` |
| 레이아웃 (layouts) | `rectangle.3.group` | `.indigo` |
| 디스플레이 (displays) | `display` | `.teal` |
| 일반 (general) | `gearshape` | `.gray` |
| 정보 (info) | `info.circle` | `.green` |

라벨 문구는 현행 유지 (일부 영문/한글 혼용 상태 그대로). `EditorTab`의 `preferredSize`/`minSize`는 제거한다 (§3에서 더 이상 사용 안 함).

### 3. 창 크기 정책 — AppState 수정

현재 `openEditor(_ tab:)`는 탭별 `preferredSize`/`minSize`로 매 호출마다 창을 리사이즈한다. 다음과 같이 바꾼다.

- **단일 기본 크기**: 첫 오픈 시 `980×680` (가장 큰 레이아웃 기준), 화면보다 크지 않게 클램프. **최소 크기**: `720×520` (역시 화면에 맞게 클램프).
- **사용자 리사이즈 + 크기 기억**: `window.setFrameAutosaveName("MyWindowManagerEditor")`로 마지막 창 프레임을 복원한다. autosave가 복원에 성공하면 기본 크기 설정을 덮어쓰지 않는다.
- **이미 열려 있을 때 다른 탭 진입**: 창을 새로 만들거나 리사이즈하지 않고, `selectedTab`만 갱신한 뒤 `makeKeyAndOrderFront`. 이를 위해 `AppState`가 `selectedTab`을 `@Published`로 소유하고, `openEditor`는 이 값만 바꾼다.
- `styleMask`는 기존대로 `.titled, .closable, .resizable, .miniaturizable` 유지.

### 4. 타이틀바 + 사이드바 글래스 (모던 룩)

- 창 타이틀바: `titlebarAppearsTransparent = true`로 두어 사이드바 vibrancy가 상단까지 이어지는 일체형 느낌. 타이틀 텍스트("My Window Manager")는 유지.
- **사이드바에 별도 배경/머티리얼을 추가하지 않는다.** `NavigationSplitView`의 사이드바는 이미 시스템 글래스(concentric glass card)이므로, 직접 배경을 깔면 이중 사각형이 된다. (메모리: navsplitview-sidebar-glass-card)

## 영향 받는 파일

- `Sources/MyWindowManager/UI/Editor/EditorWindow.swift` — `EditorRootView` 재작성, `EditorTab`에 symbol/tint 추가, preferredSize/minSize 제거.
- `Sources/MyWindowManager/App/AppState.swift` — `selectedTab` 소유, `openEditor` 단순화, autosave 적용.
- 각 편집 뷰 파일 — **무변경** (디테일 영역에서 그대로 호출).

## 검증

- 빌드 후 앱 자동 재실행(메모리: restart-after-changes)하여 육안 확인.
- 확인 항목: 사이드바 6항목 + 컬러 아이콘 표시 / 항목 클릭 시 디테일 전환 / 창 리사이즈·크기 기억 / 항목 전환 시 창 안 흔들림 / 메뉴바에서 특정 탭 진입 시 해당 항목 선택 상태로 열림.
- 스크린샷 자동 테스트는 하지 않음 (메모리: navsplitview-sidebar-glass-card — 반복 중 스크린샷 금지).
