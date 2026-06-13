# 사이드바 설정 UI 전면 개편 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 설정 창을 상단 탭바(`TabView`)에서 BetterDisplay 스타일의 사이드바 + 디테일(`NavigationSplitView`) 레이아웃으로 전면 개편한다.

**Architecture:** `EditorTab` enum에 컬러 SF Symbol 메타데이터(symbol/tint)를 추가하고 창 크기 관련 속성을 제거한다. `EditorRootView`를 `NavigationSplitView`로 재작성한다. 선택 상태를 `AppState`가 `@Published`로 소유해 창이 이미 열려 있어도 사이드바 선택만 전환되게 한다. 각 편집 뷰의 내부 로직은 무변경 — 디테일 영역에서 그대로 호출된다.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit (`NSWindow`), Swift Package Manager. 타겟 macOS 14+.

**테스트 전략 주의:** 이 프로젝트는 UI 단위 테스트 하네스가 없다. 각 태스크의 "테스트"는 `swift build` 성공 + 메모리 규칙에 따른 빌드 후 자동 재실행 육안 확인이다 (스크린샷 자동 테스트 금지 — 메모리: navsplitview-sidebar-glass-card).

---

## 구현 결과 — 계획 대비 변경점 (2026-06-13 완료)

구현 중 아래 항목이 계획과 달라졌다. 모두 더 나은 방향으로 확정되었으며 코드/커밋에 반영됨.

1. **설정 창을 수동 `NSWindow` → SwiftUI `Window` scene으로 변경 (Task 3 핵심 변경).** 계획은 `NSWindow(contentViewController:)`를 유지했으나, 그 방식에선 `NavigationSplitView` 사이드바 머티리얼이 타이틀바(신호등) 영역까지 채워지지 않았다(lldb로 머티리얼 높이가 창보다 타이틀바만큼 작음을 확인). App Store·메모처럼 SwiftUI가 윈도우를 소유하도록 `MyWindowManagerApp`에 `Window(id:)` scene을 추가하고 `.windowStyle(.hiddenTitleBar)`를 적용해 해결. `AppState.openEditor`는 NSWindow를 만들지 않고 `selectedTab`만 설정 후 `openWindow` 액션(MenuBarContent/AppState.openEditorWindow로 주입)을 호출한다. selection은 `@Binding`이 아니라 `AppState`(`@EnvironmentObject`)에서 받는다. 메모리: [[settings-window-must-be-swiftui-scene]].
2. **사이드바·정보 탭 반투명 vibrancy 추가** (계획 범위 밖, 후속 요청). `VisualEffectView`(NSViewRepresentable) 신설 — behind-window vibrancy, `followsWindowActiveState`(비활성 시 불투명), `allowsVibrancy=false` 변형. 사이드바=`.hudWindow`, 정보 탭=`.hudWindow`, 나머지 탭=불투명 `.windowBackground`.
3. **각 편집 뷰의 사소한 레이아웃 보정** (계획은 "무변경"이었으나 공용 디테일 환경에서 필요): `GeneralView`의 잔존 `.fixedSize` 제거, `LayoutEditorView` detail을 `maxHeight: .infinity`/top-leading로 고정, 프리셋·사이클·레이아웃 목록 열 `maxWidth` 제한 및 +/- 버튼을 borderless로 정리, `InfoView` 아이콘 확대·GitHub 링크 텍스트화.

> 즉 아래 Task 3 코드 블록의 NSWindow 구현은 **초기 계획안**이며, 최종 코드는 위 1번대로 SwiftUI scene이다. 현재 소스를 기준으로 볼 것.

---

### Task 1: `EditorTab`에 아이콘 메타데이터 추가 + 창 크기 속성 제거

**Files:**
- Modify: `Sources/MyWindowManager/UI/Editor/EditorWindow.swift:3-41`

이 태스크는 `EditorTab` enum만 수정한다. `preferredSize`/`minSize`를 제거하면 `AppState.swift`가 일시적으로 컴파일 에러가 나므로, 이 태스크의 빌드 검증은 Task 3 이후로 미룬다. (Task 1→2→3은 한 묶음으로 연속 실행.)

- [x] **Step 1: `EditorTab`에 symbol/tint 추가, preferredSize/minSize 제거**

`EditorWindow.swift`의 `enum EditorTab { ... }` 블록(현재 3~41행) 전체를 아래로 교체:

```swift
import SwiftUI

enum EditorTab: String, CaseIterable, Identifiable {
    case presets, cycles, layouts, displays, general, info
    var id: String { rawValue }

    var label: String {
        switch self {
        case .presets: return "Resize Presets"
        case .cycles: return "Cycles"
        case .layouts: return "Layouts"
        case .displays: return "Displays"
        case .general: return "일반"
        case .info: return "정보"
        }
    }

    /// SF Symbol name shown next to the label in the sidebar.
    var symbol: String {
        switch self {
        case .presets: return "rectangle.split.2x1"
        case .cycles: return "arrow.triangle.2.circlepath"
        case .layouts: return "rectangle.3.group"
        case .displays: return "display"
        case .general: return "gearshape"
        case .info: return "info.circle"
        }
    }

    /// Accent color applied to the sidebar icon.
    var tint: Color {
        switch self {
        case .presets: return .blue
        case .cycles: return .purple
        case .layouts: return .indigo
        case .displays: return .teal
        case .general: return .gray
        case .info: return .green
        }
    }
}
```

> 주: `label`의 한글/영문 혼용은 현행 유지 (스펙 범위 밖). `preferredSize`/`minSize`는 의도적으로 제거 — Task 3에서 창 크기 로직이 이를 더 이상 쓰지 않게 된다.

- [x] **Step 2: (검증 보류)**

이 시점에서 `swift build`는 `AppState.swift`가 제거된 `preferredSize`/`minSize`를 참조하므로 실패한다. 정상이다. Task 3까지 진행 후 빌드한다.

---

### Task 2: `EditorRootView`를 NavigationSplitView로 재작성

**Files:**
- Modify: `Sources/MyWindowManager/UI/Editor/EditorWindow.swift:43-68`

- [x] **Step 1: `EditorRootView` 교체**

`EditorWindow.swift`의 `struct EditorRootView { ... }` 블록(현재 43~68행) 전체를 아래로 교체. selection은 외부(AppState)에서 바인딩으로 주입받는다.

```swift
struct EditorRootView: View {
    @Binding var selection: EditorTab

    var body: some View {
        NavigationSplitView {
            List(EditorTab.allCases, selection: $selection) { tab in
                Label {
                    Text(tab.label)
                } icon: {
                    Image(systemName: tab.symbol)
                        .foregroundStyle(tab.tint)
                }
                .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .presets: PresetEditorView()
        case .cycles: CycleEditorView()
        case .layouts: LayoutEditorView()
        case .displays: DisplayDeadzoneView()
        case .general: GeneralView()
        case .info: InfoView()
        }
    }
}
```

> 주: `List(_:selection:)`에 `EditorTab`을 직접 쓰려면 `Hashable`이 필요하다. `EditorTab`은 `String` raw value enum이라 자동으로 `Hashable`이다 — 추가 작업 불필요. 사이드바 배경은 직접 깔지 않는다 (메모리: navsplitview-sidebar-glass-card — 시스템 글래스 위에 이중 배경 금지).

- [x] **Step 2: (검증 보류)** Task 3과 함께 빌드.

---

### Task 3: AppState — selectedTab 소유, openEditor 단순화, 창 크기 기억

**Files:**
- Modify: `Sources/MyWindowManager/App/AppState.swift:6` (프로퍼티)
- Modify: `Sources/MyWindowManager/App/AppState.swift:20-59` (`openEditor`)

- [x] **Step 1: `selectedTab` 프로퍼티 추가**

`AppState.swift`의 6행 `@Published var openedEditor: EditorTab? = nil` 아래에 추가:

```swift
    @Published var selectedTab: EditorTab = .presets
```

(기존 `openedEditor`는 다른 코드가 쓰는지와 무관하게 그대로 둔다 — 제거 범위 아님.)

- [x] **Step 2: `openEditor(_:)` 전체 교체**

20~59행의 `func openEditor(_ tab: EditorTab) { ... }` 전체를 아래로 교체:

```swift
    func openEditor(_ tab: EditorTab) {
        guard let store, let catalog, let hotkeys else { return }
        selectedTab = tab
        if let w = editorWindow {
            // 이미 열려 있으면 창을 리사이즈하지 않고 선택만 전환.
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = EditorRootView(selection: Binding(
            get: { [weak self] in self?.selectedTab ?? .presets },
            set: { [weak self] in self?.selectedTab = $0 }
        ))
        .environmentObject(store)
        .environmentObject(catalog)
        .environmentObject(hotkeys)
        let host = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: host)
        window.title = "My Window Manager"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.titlebarAppearsTransparent = true

        // 단일 기본 크기(가장 큰 레이아웃 기준), 화면보다 크지 않게 클램프.
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size
            ?? NSSize(width: 1280, height: 800)
        let margin: CGFloat = 0.92
        let defaultSize = NSSize(width: 980, height: 680)
        let minSize = NSSize(width: 720, height: 520)
        let content = NSSize(
            width: min(defaultSize.width, visible.width * margin),
            height: min(defaultSize.height, visible.height * margin)
        )
        window.contentMinSize = NSSize(
            width: min(minSize.width, content.width),
            height: min(minSize.height, content.height)
        )
        window.setContentSize(content)
        window.center()
        // 사용자가 조절한 크기를 재오픈/재실행 시 복원.
        window.setFrameAutosaveName("MyWindowManagerEditor")
        window.isReleasedWhenClosed = false
        window.delegate = WindowCloseHandler.shared
        WindowCloseHandler.shared.onClose = { [weak self] w in
            if w == self?.editorWindow { self?.editorWindow = nil }
            if w == self?.onboardingWindow { self?.onboardingWindow = nil }
        }
        editorWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
```

> 주: `setFrameAutosaveName`은 `center()`/`setContentSize` **이후**에 호출한다 — autosave에 저장된 프레임이 있으면 그걸 복원하고, 없으면 방금 설정한 기본 크기·중앙 위치를 유지한다. `openPresetEditor()`/`openLayoutEditor()` 헬퍼(17~18행)는 그대로 두면 된다 — 내부적으로 `openEditor`를 호출한다.

- [x] **Step 3: 빌드 검증 (Task 1·2·3 통합)**

Run: `swift build`
Expected: 컴파일 성공 (에러·경고 없음). `EditorRootView(initialTab:)` 관련 에러가 없어야 함 — 27행이 새 `selection:` 바인딩 형태로 바뀌었기 때문.

- [x] **Step 4: 빌드 후 앱 자동 재실행 + 육안 확인**

Run: `make run`
확인 항목 (메모리: restart-after-changes — 코드 변경 후 빌드·재실행 자동 수행):
- 설정 창에 좌측 사이드바 6항목이 컬러 아이콘과 함께 표시된다 (프리셋=파랑, 사이클=보라, 레이아웃=인디고, 디스플레이=청록, 일반=회색, 정보=초록).
- 사이드바 항목 클릭 시 우측 디테일이 해당 편집 화면으로 전환된다.
- 창을 리사이즈할 수 있고, 닫았다 다시 열면 마지막 크기가 복원된다.
- 항목을 전환해도 창 크기가 흔들리지 않는다.
- 메뉴바에서 "프리셋 편집" / "레이아웃 편집" 진입 시 해당 항목이 선택된 상태로 열린다.
- 사이드바에 이중 배경(테두리 안 또 다른 사각형)이 없다.

- [x] **Step 5: Commit**

```bash
git add Sources/MyWindowManager/UI/Editor/EditorWindow.swift Sources/MyWindowManager/App/AppState.swift
git commit -m "feat: redesign settings as NavigationSplitView sidebar (BetterDisplay style)"
```

---

## Self-Review

**Spec coverage 확인:**
- §1 NavigationSplitView 평면 6항목 → Task 2 ✓
- §2 컬러 SF Symbol 아이콘 (symbol/tint 매핑) → Task 1 ✓
- §3 단일 기본 크기 980×680 / 최소 720×520, 리사이즈+크기 기억(autosave), 이미 열려 있을 때 선택만 전환, selectedTab을 AppState 소유 → Task 1(속성 제거)·Task 3 ✓
- §4 titlebarAppearsTransparent, 사이드바 배경 미추가 → Task 2·Task 3 ✓
- 범위 밖(편집 뷰 무변경) → 어떤 태스크도 편집 뷰 파일을 건드리지 않음 ✓

**Placeholder scan:** 없음 — 모든 코드 블록이 완전한 교체본.

**Type consistency:** `EditorTab`은 Hashable(String raw)·Identifiable로 List selection에 사용 가능. `EditorRootView`는 `@Binding var selection: EditorTab`, `AppState`는 `selectedTab` 바인딩을 주입 — 시그니처 일치. `openEditor`가 더 이상 `preferredSize`/`minSize`를 참조하지 않음 (Task 1에서 제거한 것과 일치).
