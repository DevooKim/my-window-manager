# My Window Manager (Swift) — macOS 네이티브 윈도우 매니저

> Claude Code에게 이 문서를 주고 단계별로 구현 요청하면 됩니다.
> 각 Phase는 독립적으로 동작 가능하도록 설계되어 있습니다.

---

## 1. 프로젝트 개요

### 목적
Raycast Window Manager / Rectangle Pro / Loop 수준의 macOS 네이티브 윈도우 매니저를 직접 만든다. **시각적 편집기**가 핵심 차별점.

### 핵심 기능 3가지
1. **레이아웃 일괄 적용**: 지정된 앱들을 지정된 모니터의 지정된 위치/크기로 한 번에 띄우기
2. **활성 윈도우 커스텀 리사이즈**: "Left Half + Height 200px" 같은 비표준 사이즈 프리셋
3. **🆕 시각적 편집기**: 드래그로 영역 그리기 + 숫자 정밀 입력으로 프리셋/레이아웃 편집

### 왜 Swift 네이티브
- 시각적 편집기(드래그로 영역 그리기) → SwiftUI `DragGesture`가 압도적으로 깔끔
- 네이티브 .app 단일 배포
- SwiftUI 한 트리에서 메뉴바 + 설정창 + 시각편집기 모두 일관
- AX API 직접 다루는 학습 가치

### 범위
- **v1 포함**: 메뉴바, 레이아웃/프리셋 적용, 시각편집기, JSON 설정, 글로벌 단축키, AX 권한 처리
- **v1 제외**: App Store, iCloud 동기화, 윈도우 사이클링
- **v2 후보**: undo, 자동 모니터 매칭, 레이아웃 export/share

---

## 2. 사전 준비

### 필수
- macOS 13+ (Ventura)
- Xcode 15+
- Swift 5.9+

### SPM 의존성
```
https://github.com/soffes/HotKey  # 글로벌 단축키
```

### 권한
- **Accessibility 권한 필수** — 첫 실행 시 안내 UI

### Info.plist
```xml
<key>LSUIElement</key>
<true/>  <!-- Dock 숨김, 메뉴바 전용 -->

<key>NSAccessibilityUsageDescription</key>
<string>My Window Manager needs Accessibility access to move and resize windows.</string>
```

### Entitlements
- App Sandbox: **OFF** (AX API 사용 위해)
- Hardened Runtime: ON (notarization 위해)

---

## 3. 프로젝트 구조

```
MyWindowManager/
├── MyWindowManager.xcodeproj
├── MyWindowManager/
│   ├── App/
│   │   ├── MyWindowManagerApp.swift          # @main 진입점
│   │   └── AppDelegate.swift              # NSApplication delegate
│   ├── Core/
│   │   ├── WindowController.swift         # AX API 래퍼
│   │   ├── ScreenHelper.swift             # 좌표계 변환
│   │   ├── AppLauncher.swift              # 앱 launch + 윈도우 polling
│   │   └── AccessibilityManager.swift     # AX 권한 + 모니터링
│   ├── Models/
│   │   ├── FrameUnit.swift                # ratio | pixels enum
│   │   ├── RelativeFrame.swift            # x/y/w/h 묶음
│   │   ├── ResizePreset.swift             # 기능 2 모델
│   │   ├── AppPlacement.swift             # 레이아웃의 한 칸
│   │   ├── Layout.swift                   # 기능 1 모델
│   │   └── HotkeyConfig.swift             # 단축키 모델
│   ├── Features/
│   │   ├── Resize/ResizeApplier.swift     # 기능 2 엔진
│   │   └── Layout/LayoutApplier.swift     # 기능 1 엔진
│   ├── Storage/
│   │   ├── ConfigStore.swift              # JSON 영속화
│   │   └── AppCatalog.swift               # 설치된 앱 목록 캐시
│   ├── Hotkey/
│   │   └── HotkeyRegistry.swift           # 단축키 등록/해제
│   ├── UI/
│   │   ├── MenuBar/
│   │   │   └── MenuBarContent.swift       # MenuBarExtra 컨텐츠
│   │   ├── Editor/
│   │   │   ├── EditorWindow.swift         # 편집기 윈도우
│   │   │   ├── PresetEditorView.swift     # 리사이즈 프리셋 편집
│   │   │   ├── LayoutEditorView.swift     # 레이아웃 편집
│   │   │   ├── MonitorCanvas.swift        # 모니터 시각화 + 드래그
│   │   │   └── PlacementInspector.swift   # 우측 정밀 입력 패널
│   │   └── Onboarding/
│   │       └── AccessibilityPromptView.swift
│   └── Assets.xcassets
├── MyWindowManagerTests/
└── README.md
```

---

## 4. 기능 명세

### 기능 1: 레이아웃 일괄 적용

#### 동작
1. `launchIfNeeded=true`인 앱들을 동시 launch (`TaskGroup`)
2. 각 앱의 메인 윈도우가 준비될 때까지 polling (최대 3초, 150ms 간격)
3. 풀스크린 해제 후 setFrame
4. 적용 완료 토스트

#### 모델
```swift
struct Layout: Codable, Identifiable {
    let id: UUID
    var name: String
    var placements: [AppPlacement]
    var hotkey: HotkeyConfig?
}

struct AppPlacement: Codable, Identifiable {
    let id: UUID
    var bundleId: String              // "com.google.Chrome"
    var displayMatcher: DisplayMatcher
    var frame: RelativeFrame
    var launchIfNeeded: Bool
}

enum DisplayMatcher: Codable {
    case primary
    case index(Int)                    // 0, 1, 2...
    case name(String)                  // "LG UltraFine"
}
```

---

### 기능 2: 활성 윈도우 커스텀 리사이즈

#### 동작
1. 프론트모스트 앱의 포커스 윈도우 가져오기
2. 윈도우가 속한 디스플레이의 visibleFrame 계산
3. 프리셋 각 차원을 ratio/px로 해석
4. 풀스크린 해제 후 setFrame

#### 모델
```swift
enum FrameUnit: Codable, Hashable {
    case ratio(Double)        // visibleFrame 대비 (0.0~1.0)
    case pixels(CGFloat)      // 절대 픽셀
}

struct RelativeFrame: Codable {
    var x: FrameUnit
    var y: FrameUnit
    var width: FrameUnit
    var height: FrameUnit
}

struct ResizePreset: Codable, Identifiable {
    let id: UUID
    var name: String
    var frame: RelativeFrame
    var hotkey: HotkeyConfig?
}
```

#### 핵심 요구사항: "Left + Height 200px"
```swift
ResizePreset(
    id: UUID(),
    name: "Left + 200px",
    frame: RelativeFrame(
        x: .ratio(0),
        y: .ratio(0),
        width: .ratio(0.5),
        height: .pixels(200)   // ← 비표준 픽셀 고정
    ),
    hotkey: HotkeyConfig(key: .one, mods: [.control, .option])
)
```

#### 기본 프리셋 카탈로그
| 프리셋 | x | y | w | h | 단축키 |
|---|---|---|---|---|---|
| Left Half | r0 | r0 | r0.5 | r1.0 | `⌃⌥H` |
| Right Half | r0.5 | r0 | r0.5 | r1.0 | `⌃⌥L` |
| Top Half | r0 | r0 | r1.0 | r0.5 | `⌃⌥K` |
| Bottom Half | r0 | r0.5 | r1.0 | r0.5 | `⌃⌥J` |
| Maximize | r0 | r0 | r1.0 | r1.0 | `⌃⌥M` |
| Center 80% | r0.1 | r0.1 | r0.8 | r0.8 | `⌃⌥C` |
| **Left + 200px** | r0 | r0 | r0.5 | **px200** | `⌃⌥1` |
| **Top Strip 300px** | r0 | r0 | r1.0 | **px300** | `⌃⌥2` |

(r=ratio, px=pixels)

---

### 🆕 기능 3: 시각적 편집기

이게 이 프로젝트의 **핵심 차별점**. raycast / Rectangle 무료판에 없는 UX.

#### 3-1. 프리셋 편집기 (단일 모니터)

```
┌──────────────────────────────────────────────┐
│ Name: [Left + 200px              ]            │
│ ───────────────────────────────────────────── │
│                                              │
│   ┌────────────────────────────┐             │
│   │ ┌─────────┐                │             │ ← Monitor canvas
│   │ │░░░░░░░░░│   (preset      │             │   16:10 비율 유지
│   │ │░░░░░░░░░│    area)       │             │   드래그로 영역 변경
│   │ │░░░░░░░░░│                │             │   모서리 드래그로 리사이즈
│   │ └─────────┘                │             │
│   │                            │             │
│   │                            │             │
│   └────────────────────────────┘             │
│                                              │
│ ───────────────────────────────────────────── │
│ X:  [0.0  ] [ratio▾]  ← FrameUnit picker     │ ← Precise input
│ Y:  [0.0  ] [ratio▾]                          │   (드래그와 양방향 동기)
│ W:  [0.5  ] [ratio▾]                          │
│ H:  [200  ] [px▾]      ← 핵심 케이스          │
│                                              │
│ Hotkey: [⌃⌥1] [Change...]                    │
│                                              │
│ [Apply Now (Preview)] [Cancel] [Save]        │
└──────────────────────────────────────────────┘
```

**상호작용 규칙**
- 캔버스 클릭+드래그 = 새 영역 그리기 (즉시 숫자 입력란 업데이트)
- 영역 모서리 핸들 드래그 = 리사이즈
- 영역 본체 드래그 = 이동
- 숫자 입력 변경 = 캔버스 즉시 반영
- FrameUnit 토글 (ratio ↔ px) = 현재 값을 단위 변환해서 유지
  - 예: ratio 0.5에서 px로 토글 → 모니터 너비 × 0.5 픽셀로 변환

**드래그 → 단위 결정 로직**
- 캔버스에서 드래그하면 기본은 ratio로 입력
- 사용자가 px로 수동 변경한 차원은 px 유지
- "Snap to ratio" 옵션 (1/4, 1/3, 1/2 등 격자)

#### 3-2. 레이아웃 편집기 (다중 모니터)

```
┌──────────────────────────────────────────────────┐
│ Name: [작업 모드                  ]              │
│ ───────────────────────────────────────────────  │
│                                                  │
│  Display 1 (Built-in)         Display 2 (LG)     │
│  ┌────────────────────┐       ┌──────────────┐   │
│  │ ┌──────┐ ┌───────┐ │       │ ┌──────────┐ │   │
│  │ │Chrome│ │ Slack │ │       │ │ Ghostty  │ │   │
│  │ │ 70%  │ │  30%  │ │       │ │  100%    │ │   │
│  │ └──────┘ └───────┘ │       │ └──────────┘ │   │
│  └────────────────────┘       └──────────────┘   │
│                                                  │
│  [+ Add Placement]                               │
│ ───────────────────────────────────────────────  │
│ Selected: Chrome on Display 1                    │
│   App:   [Google Chrome           ▾]             │
│   X: [0.0] Y: [0.0] W: [0.7] H: [1.0]           │
│   ☑ Launch if needed                             │
│                                                  │
│ Hotkey: [⌃⌥F1]                                   │
│ [Apply Now] [Cancel] [Save]                      │
└──────────────────────────────────────────────────┘
```

**상호작용 규칙**
- 각 모니터에 placement 추가 → 빈 영역에서 드래그
- placement 클릭 → 우측 inspector에 상세 표시
- placement 본체/모서리 드래그 = 이동/리사이즈
- placement 다른 모니터로 드래그 = 이동 (Display matcher 변경)
- App 선택: 설치된 .app 스캔한 카탈로그에서 검색
- 모니터 박스는 실제 모니터 해상도 비율 유지

---

## 5. 구현 단계 (Phase)

### Phase 1 — 토대 (1일)
- [ ] Xcode 프로젝트 생성 (SwiftUI, macOS app)
- [ ] `LSUIElement = YES`, MenuBarExtra 빈 메뉴
- [ ] Accessibility 권한 체크 + onboarding 화면
- [ ] HotKey SPM 추가
- [ ] **검증**: 앱 실행 → 권한 안내 → 메뉴바에 아이콘 표시

### Phase 2 — Core (1일)
- [ ] `WindowController` (focusedWindow, setFrame, getFrame, unsetFullscreen)
- [ ] `ScreenHelper` (Cocoa↔AX 좌표 변환, visibleFrame, displayID)
- [ ] **검증**: 하드코딩된 frame으로 Safari 윈도우 이동 성공

### Phase 3 — 기능 2 엔진 (1일)
- [ ] `FrameUnit`, `RelativeFrame`, `ResizePreset` 모델
- [ ] `ResizeApplier.apply(preset:)`
- [ ] 멀티 디스플레이에서 좌표계 검증
- [ ] **검증**: "Left + 200px" 하드코딩 프리셋이 어느 모니터에서든 정확히 동작

### Phase 4 — 단축키 + 설정 저장 (1일)
- [ ] `HotkeyConfig` 모델 + `HotkeyRegistry`
- [ ] `ConfigStore` (JSON, `~/Library/Application Support/MyWindowManager/config.json`)
- [ ] 기본 프리셋 8개 시드 데이터
- [ ] 메뉴바에 프리셋 리스트 표시
- [ ] **검증**: 8개 프리셋 모두 단축키로 동작, 앱 재실행 후에도 유지

### Phase 5 — 기능 1 엔진 (1.5일)
- [ ] `AppLauncher` (launch + 윈도우 polling)
- [ ] `Layout`, `AppPlacement`, `DisplayMatcher` 모델
- [ ] `LayoutApplier.apply(layout:)` — TaskGroup 동시 launch
- [ ] `AppCatalog` (설치된 .app 스캔)
- [ ] 기본 레이아웃 1개 시드
- [ ] **검증**: 모든 앱 종료 상태에서 단축키 → 자동 launch + 정확한 배치

### Phase 6 — 메뉴바 UI (0.5일)
- [ ] MenuBarExtra 구조: 레이아웃 / 프리셋 / 설정 / 종료
- [ ] 각 항목 클릭 시 적용
- [ ] **검증**: 메뉴바에서 마우스로 모든 프리셋/레이아웃 실행 가능

### Phase 7 — 시각편집기: 프리셋 (2일) ⭐
- [ ] `MonitorCanvas` SwiftUI view
  - 모니터 비율 유지 사각형
  - 영역 사각형 (드래그 가능)
  - 4개 모서리 핸들
  - 본체 드래그
- [ ] `PlacementInspector` 우측 패널
  - X/Y/W/H 입력 + FrameUnit picker
  - ratio↔px 토글 시 자동 변환
- [ ] `PresetEditorView` (전체 조합)
- [ ] Hotkey 캡처 UI
- [ ] Apply Now 버튼 (미리보기)
- [ ] **검증**: 드래그로 임의 영역 그리고 저장 → 단축키로 실제 적용 일치

### Phase 8 — 시각편집기: 레이아웃 (2일) ⭐
- [ ] 다중 모니터 캔버스 (실제 배치 반영)
- [ ] Placement 추가/이동/리사이즈/삭제
- [ ] 모니터 간 드래그로 이동
- [ ] App picker (검색 가능 카탈로그)
- [ ] **검증**: 시각적으로 만든 레이아웃이 실제 적용 시 일치

### Phase 9 — Polish (1일)
- [ ] 적용 완료 토스트 (`NSUserNotification` 또는 floating panel)
- [ ] 풀스크린/최소화 윈도우 graceful 처리
- [ ] 디스플레이 hot-plug 감지 + 단축키 재등록
- [ ] AX 권한 revoke 감지 → 재요청
- [ ] 에러 로그 (`os_log`)
- [ ] **검증**: 모든 엣지 케이스 통과

### Phase 10 — 배포 (0.5일)
- [ ] Developer ID 서명
- [ ] notarization
- [ ] DMG 생성
- [ ] README + 스크린샷

**총 예상 기간: 약 11일 (Claude Code 활용 시 절반 가능)**

---

## 6. 핵심 코드 템플릿

### `Models/FrameUnit.swift`
```swift
import Foundation
import CoreGraphics

enum FrameUnitType: String, Codable { case ratio, pixels }

enum FrameUnit: Codable, Hashable {
    case ratio(Double)
    case pixels(CGFloat)
    
    var type: FrameUnitType {
        switch self {
        case .ratio:  return .ratio
        case .pixels: return .pixels
        }
    }
    
    /// 주어진 모니터 차원에서 픽셀 값으로 해석
    func resolve(in total: CGFloat) -> CGFloat {
        switch self {
        case .ratio(let r):   return total * CGFloat(r)
        case .pixels(let px): return px
        }
    }
    
    /// 단위 토글 시 값 보존 (모니터 차원 기준으로 변환)
    func converted(to type: FrameUnitType, total: CGFloat) -> FrameUnit {
        let px = resolve(in: total)
        switch type {
        case .ratio:  return .ratio(Double(px / total))
        case .pixels: return .pixels(px)
        }
    }
    
    // Codable
    private enum CodingKeys: String, CodingKey { case type, value }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(FrameUnitType.self, forKey: .type)
        let value = try c.decode(Double.self, forKey: .value)
        switch type {
        case .ratio:  self = .ratio(value)
        case .pixels: self = .pixels(CGFloat(value))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ratio(let v):
            try c.encode(FrameUnitType.ratio, forKey: .type)
            try c.encode(v, forKey: .value)
        case .pixels(let v):
            try c.encode(FrameUnitType.pixels, forKey: .type)
            try c.encode(Double(v), forKey: .value)
        }
    }
}
```

### `Core/WindowController.swift`
```swift
import ApplicationServices
import AppKit

enum WindowController {
    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &win
        ) == .success, let win else { return nil }
        return (win as! AXUIElement)
    }
    
    static func firstWindow(of bundleId: String) -> AXUIElement? {
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleId).first
        else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref)
        return (ref as? [AXUIElement])?.first
    }
    
    static func setFrame(_ window: AXUIElement, frame: CGRect) {
        unsetFullscreen(window)
        var pos = frame.origin
        var size = frame.size
        if let p = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
        }
        if let s = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s)
        }
        // 일부 앱은 size 적용 후 position이 어긋남 → 한 번 더
        if let p = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
        }
    }
    
    static func getFrame(_ window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        guard let posRef, let sizeRef else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }
    
    static func unsetFullscreen(_ window: AXUIElement) {
        var val: CFTypeRef?
        AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &val)
        if let isFull = val as? Bool, isFull {
            AXUIElementSetAttributeValue(
                window, "AXFullScreen" as CFString, false as CFTypeRef
            )
            Thread.sleep(forTimeInterval: 0.2)
        }
    }
}
```

### `Core/ScreenHelper.swift`
```swift
import AppKit

enum ScreenHelper {
    /// NSScreen.visibleFrame을 AX 좌표계(top-left origin)로 변환
    static func axVisibleFrame(of screen: NSScreen) -> CGRect {
        guard let primary = NSScreen.screens.first else { return screen.visibleFrame }
        let f = screen.visibleFrame
        return CGRect(
            x: f.minX,
            y: primary.frame.maxY - f.maxY,
            width: f.width,
            height: f.height
        )
    }
    
    /// 윈도우가 속한 화면 찾기
    static func screen(containing window: AXUIElement) -> NSScreen? {
        guard let frame = WindowController.getFrame(window) else { return nil }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { axVisibleFrame(of: $0).contains(center) }
            ?? NSScreen.main
    }
    
    /// DisplayMatcher → NSScreen 해석
    static func resolve(_ matcher: DisplayMatcher) -> NSScreen? {
        switch matcher {
        case .primary:
            return NSScreen.screens.first
        case .index(let i):
            return i < NSScreen.screens.count ? NSScreen.screens[i] : nil
        case .name(let name):
            return NSScreen.screens.first { $0.localizedName == name }
        }
    }
}
```

### `Features/Resize/ResizeApplier.swift`
```swift
import AppKit

enum ResizeApplier {
    static func apply(_ preset: ResizePreset) {
        guard let win = WindowController.focusedWindow(),
              let screen = ScreenHelper.screen(containing: win) else { return }
        
        let area = ScreenHelper.axVisibleFrame(of: screen)
        let f = preset.frame
        
        let frame = CGRect(
            x: area.minX + f.x.resolve(in: area.width),
            y: area.minY + f.y.resolve(in: area.height),
            width: f.width.resolve(in: area.width),
            height: f.height.resolve(in: area.height)
        )
        WindowController.setFrame(win, frame: frame)
    }
}
```

### `Features/Layout/LayoutApplier.swift`
```swift
import AppKit

enum LayoutApplier {
    static func apply(_ layout: Layout) async {
        // 1단계: 필요한 앱들 동시 launch
        await withTaskGroup(of: Void.self) { group in
            for p in layout.placements where p.launchIfNeeded {
                group.addTask { await ensureLaunched(p.bundleId) }
            }
        }
        
        // 2단계: 각 placement 적용
        for p in layout.placements {
            await place(p)
        }
    }
    
    private static func ensureLaunched(_ bundleId: String) async {
        if NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleId).first != nil {
            return
        }
        guard let url = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleId) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
    
    private static func place(_ p: AppPlacement) async {
        guard let win = await waitForWindow(bundleId: p.bundleId, timeout: 3.0),
              let screen = ScreenHelper.resolve(p.displayMatcher) else { return }
        
        let area = ScreenHelper.axVisibleFrame(of: screen)
        let f = p.frame
        let frame = CGRect(
            x: area.minX + f.x.resolve(in: area.width),
            y: area.minY + f.y.resolve(in: area.height),
            width: f.width.resolve(in: area.width),
            height: f.height.resolve(in: area.height)
        )
        WindowController.setFrame(win, frame: frame)
    }
    
    private static func waitForWindow(
        bundleId: String, timeout: TimeInterval
    ) async -> AXUIElement? {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if let win = WindowController.firstWindow(of: bundleId) {
                try? await Task.sleep(nanoseconds: 200_000_000)
                return win
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return nil
    }
}
```

### `UI/Editor/MonitorCanvas.swift` (드래그 핵심)
```swift
import SwiftUI

/// 모니터 비율을 유지하는 사각형 + 드래그 가능한 영역
struct MonitorCanvas: View {
    let monitorPixelSize: CGSize     // 실제 모니터 해상도
    @Binding var area: RelativeFrame // 0~1 비율 (px도 표현)
    
    @State private var dragMode: DragMode = .idle
    
    enum DragMode {
        case idle
        case newArea(start: CGPoint)
        case moveBody(offset: CGSize)
        case resizeCorner(Corner, original: RelativeFrame)
    }
    
    var monitorAspect: CGFloat {
        monitorPixelSize.width / monitorPixelSize.height
    }
    
    var body: some View {
        GeometryReader { geo in
            let canvas = fitAspect(geo.size, aspect: monitorAspect)
            let origin = CGPoint(
                x: (geo.size.width - canvas.width) / 2,
                y: (geo.size.height - canvas.height) / 2
            )
            let areaRect = pixelRect(of: area, canvas: canvas)
            
            ZStack(alignment: .topLeading) {
                // 모니터 외곽
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary, lineWidth: 2)
                    .frame(width: canvas.width, height: canvas.height)
                    .offset(x: origin.x, y: origin.y)
                
                // 영역 표시
                Rectangle()
                    .fill(Color.accentColor.opacity(0.35))
                    .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 2))
                    .frame(width: areaRect.width, height: areaRect.height)
                    .offset(x: origin.x + areaRect.minX, y: origin.y + areaRect.minY)
                    .gesture(bodyDragGesture(canvas: canvas))
                
                // 4개 모서리 핸들
                ForEach(Corner.allCases, id: \.self) { corner in
                    cornerHandle(corner: corner,
                                 areaRect: areaRect,
                                 origin: origin,
                                 canvas: canvas)
                }
            }
            // 빈 곳 드래그 = 새 영역
            .contentShape(Rectangle())
            .gesture(newAreaGesture(origin: origin, canvas: canvas))
        }
        .aspectRatio(monitorAspect, contentMode: .fit)
    }
    
    // MARK: - Helpers (Phase 7에서 풀 구현)
    
    private func fitAspect(_ size: CGSize, aspect: CGFloat) -> CGSize {
        let w = min(size.width, size.height * aspect)
        let h = w / aspect
        return CGSize(width: w, height: h)
    }
    
    private func pixelRect(of frame: RelativeFrame, canvas: CGSize) -> CGRect {
        // RelativeFrame을 canvas 좌표계로 변환
        // ratio는 직접, px는 monitorPixelSize 기준 비율로
        let x = frame.x.resolve(in: monitorPixelSize.width) / monitorPixelSize.width * canvas.width
        let y = frame.y.resolve(in: monitorPixelSize.height) / monitorPixelSize.height * canvas.height
        let w = frame.width.resolve(in: monitorPixelSize.width) / monitorPixelSize.width * canvas.width
        let h = frame.height.resolve(in: monitorPixelSize.height) / monitorPixelSize.height * canvas.height
        return CGRect(x: x, y: y, width: w, height: h)
    }
    
    private func newAreaGesture(origin: CGPoint, canvas: CGSize) -> some Gesture {
        // 빈 곳에서 시작한 드래그 → 새 영역 정의
        // Phase 7에서 구현
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                // 좌표 변환 → area 업데이트
            }
            .onEnded { _ in dragMode = .idle }
    }
    
    private func bodyDragGesture(canvas: CGSize) -> some Gesture {
        // 영역 본체 드래그 → 이동
        DragGesture()
            .onChanged { value in
                // area.x, area.y 업데이트 (단위 보존)
            }
            .onEnded { _ in dragMode = .idle }
    }
    
    @ViewBuilder
    private func cornerHandle(
        corner: Corner, areaRect: CGRect,
        origin: CGPoint, canvas: CGSize
    ) -> some View {
        let handleSize: CGFloat = 10
        let pos = corner.position(in: areaRect)
        Circle()
            .fill(Color.accentColor)
            .frame(width: handleSize, height: handleSize)
            .offset(
                x: origin.x + pos.x - handleSize/2,
                y: origin.y + pos.y - handleSize/2
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // corner 따라 area 리사이즈
                    }
            )
    }
}

enum Corner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
    
    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:     return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:    return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:  return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}
```

(상세 드래그 로직은 Phase 7에서 Claude Code가 완성)

---

## 7. JSON 설정 예시

`~/Library/Application Support/MyWindowManager/config.json`

```json
{
  "version": 1,
  "presets": [
    {
      "id": "1F3D8E...",
      "name": "Left + 200px",
      "frame": {
        "x":      { "type": "ratio",  "value": 0 },
        "y":      { "type": "ratio",  "value": 0 },
        "width":  { "type": "ratio",  "value": 0.5 },
        "height": { "type": "pixels", "value": 200 }
      },
      "hotkey": { "key": "1", "mods": ["control", "option"] }
    }
  ],
  "layouts": [
    {
      "id": "2A...",
      "name": "작업 모드",
      "hotkey": { "key": "F1", "mods": ["control", "option"] },
      "placements": [
        {
          "id": "...",
          "bundleId": "com.google.Chrome",
          "displayMatcher": { "type": "primary" },
          "frame": {
            "x":      { "type": "ratio", "value": 0 },
            "y":      { "type": "ratio", "value": 0 },
            "width":  { "type": "ratio", "value": 0.7 },
            "height": { "type": "ratio", "value": 1.0 }
          },
          "launchIfNeeded": true
        },
        {
          "id": "...",
          "bundleId": "com.tinyspeck.slackmacgap",
          "displayMatcher": { "type": "primary" },
          "frame": {
            "x":      { "type": "ratio", "value": 0.7 },
            "y":      { "type": "ratio", "value": 0 },
            "width":  { "type": "ratio", "value": 0.3 },
            "height": { "type": "ratio", "value": 1.0 }
          },
          "launchIfNeeded": true
        }
      ]
    }
  ]
}
```

---

## 8. 검증 체크리스트

### 기능 2 — 리사이즈
- [ ] Chrome 포커스 → `⌃⌥H` → 정확히 왼쪽 절반
- [ ] Slack 포커스 → `⌃⌥1` → 왼쪽 절반, 높이 정확히 200px
- [ ] 풀스크린 상태에서 단축키 → 풀스크린 해제 후 적용
- [ ] 외장 모니터의 윈도우 → 해당 모니터 기준으로 적용
- [ ] 메뉴바/Dock 영역 미침범

### 기능 1 — 레이아웃
- [ ] 모든 앱 종료 상태에서 단축키 → 자동 launch + 배치
- [ ] 일부만 실행된 상태 → 미실행 launch + 모두 재배치
- [ ] 외장 모니터 미연결 → graceful fallback
- [ ] 같은 단축키 재실행 → 동일 결과 (idempotent)

### 기능 3 — 시각편집기
- [ ] 캔버스 드래그로 새 영역 그리기 → 숫자 입력란 실시간 업데이트
- [ ] 숫자 입력 변경 → 캔버스 즉시 반영
- [ ] FrameUnit 토글 (ratio↔px) → 값 보존 (모니터 변환)
- [ ] 모서리 핸들 드래그 → 정확한 리사이즈
- [ ] Apply Now → 실제 윈도우 적용해서 즉시 확인
- [ ] 시각적으로 만든 프리셋과 단축키 적용 결과 일치

### 엣지 케이스
- [ ] AX 권한 revoke 후 단축키 → 재요청 onboarding
- [ ] 앱 launch 5초 이상 걸림 → graceful timeout
- [ ] 디스플레이 hot-plug 직후 단축키
- [ ] 앱 최소 윈도우 크기보다 작게 설정 → 실제 적용 frame 차이 표시

---

## 9. 설계 결정 사항

| 항목 | 결정 | 이유 |
|---|---|---|
| 언어 | Swift 5.9 | 네이티브, SwiftUI 활용 |
| UI | SwiftUI (메뉴바도 MenuBarExtra) | 일관성, 학습가치 |
| 좌표계 | AX(top-left) 내부 통일 | AX API 자연스러움 |
| 영역 표현 | RelativeFrame (FrameUnit 조합) | ratio/px 혼용 가능 |
| 모니터 식별 | DisplayMatcher (primary/index/name) | 유연함 + fallback |
| 설정 영속화 | JSON, Application Support | 사람이 읽기 가능 |
| 단축키 | soffes/HotKey | Rectangle도 사용, 검증됨 |
| 배포 | Developer ID 서명 + notarization | App Store 미사용 (AX 권한) |
| 편집 UX | 드래그 기본 + 숫자 보조 | Raycast/Rectangle Pro 패턴 |

---

## 10. Claude Code 작업 지시 예시

### 분할 실행 (권장)
```
@my-window-manager-swift-spec.md Phase 1부터 시작해줘.
- ~/Dev/workspace 에 MyWindowManager 프로젝트 생성
- Xcode 프로젝트 구조 + Info.plist + Accessibility 권한 안내까지
- 끝나면 검증 단계 안내 후 Phase 2 진행 여부 확인
```

### 일괄 실행
```
@my-window-manager-swift-spec.md Phase 1~4 일괄 구현해줘.
- 각 Phase 끝날 때 검증 체크리스트 출력
- 핵심 파일은 보여주고, 보일러플레이트는 요약만
- Phase 5 진입 전 멈춰서 동작 확인 요청
```

### 시각편집기는 별도 세션 권장
```
@my-window-manager-swift-spec.md Phase 7 (프리셋 편집기) 구현해줘.
- MonitorCanvas는 단계별로 (사각형 → 영역 → 드래그 → 핸들 → 신규 영역 드래그)
- 각 단계마다 Preview에서 확인 가능하게
- SwiftUI Preview에서 모의 모니터 데이터로 테스트 가능하게
```

---

## 11. 참고할 오픈소스

- **Rectangle** (MIT, Swift) — AX API 패턴, HotKey 사용 정석
  - https://github.com/rxhanson/Rectangle
- **Loop** (Swift, SwiftUI) — 모던 SwiftUI 구조 + 비주얼 편집기 영감
  - https://github.com/MrKai77/Loop
- **Amethyst** — 타일링 매니저, layout engine 구조 참고
- **yabai** — 더 깊은 동작 원리 (단, SIP 비활성화 영역 있음)

---

## 끝.

**예상 결과물**: 단일 .app, 메뉴바에서 모든 기능 액세스 가능, 시각 편집기로 raycast 이상의 UX.

**진행 방식**: Phase 1~6 (엔진 + 기본 UI) 먼저 → 실제로 며칠 써보고 → Phase 7~8 (편집기) → Phase 9~10 (배포).

막히면 Phase 번호 + 에러 로그 가져오면 디버그 같이 함.
