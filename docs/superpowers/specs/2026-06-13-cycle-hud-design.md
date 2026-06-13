# 사이클 HUD 오버레이 — 설계 문서

- **날짜**: 2026-06-13
- **대상**: 사이클 적용 시 화면 중앙 HUD (`HotkeyRegistry.advanceCycle`, 신규 HUD 컴포넌트, `ConfigStore`)
- **참조**: macOS 시스템 볼륨/밝기 HUD (자동 페이드아웃 동작)

## 목표

사이클 핫키(또는 메뉴바 클릭)로 사이클을 돌릴 때, 화면 중앙에 HUD 오버레이를 띄워 **사이클 내 프리셋 목록**과 **현재 적용된 프리셋 위치**를 표시한다.

## 핵심 결정 (사용자 승인됨)

1. **HUD 위치/형태 = 화면 중앙 카드.** 두 스타일을 설정에서 선택: 세로 목록(list) / 가로 썸네일(thumbnails).
2. **사라지는 시점 = 자동 페이드아웃.** 마지막 입력 후 ~1.2초 뒤 사라지고, 연속 입력 시 타이머 리셋(계속 표시). macOS 볼륨 HUD 방식.
3. **설정 = 끄기 / 세로 목록 / 가로 썸네일, 기본값 = 가로 썸네일.** 사용자가 HUD를 완전히 끌 수 있다.

## 설계

### 1. 동작 흐름

- `HotkeyRegistry.advanceCycle(id:)`에서 `ResizeApplier.apply(...)` 직후, `store.cycleHUDStyle`를 읽어 `CycleHUDController.shared.show(...)` 호출.
- HUD는 마지막 호출 후 1.2초 디바운스 타이머로 페이드아웃. 연속 호출 시 타이머 리셋.
- `style == .off`면 컨트롤러가 아무것도 하지 않는다.

### 2. HUD 윈도우

- 별도 `NSPanel`: `.nonactivatingPanel`, borderless, `.floating` level, `ignoresMouseEvents = true`(클릭 통과), `isOpaque = false`, `backgroundColor = .clear`. 포커스를 뺏지 않는다.
- 패널은 한 번 만들어 재사용. 현재 화면(`NSScreen.main ?? .screens.first`) 중앙에 배치.
- 내용은 SwiftUI 뷰를 `NSHostingView`로 그림. 표시/숨김은 alpha 페이드(0↔1) 애니메이션.

### 3. HUD 스타일

`ConfigStore`에 `cycleHUDStyle: CycleHUDStyle` 추가. 설정 UI(사이클 탭 상단)에 Picker(끄기/목록/썸네일). 기본값 `.thumbnails`.

- **세로 목록(list):** 사이클명(상단, 작은 회색) + 프리셋 이름을 세로로 나열, 현재 항목을 강조색 배경으로 하이라이트.
- **가로 썸네일(thumbnails):** 사이클명 + "n/total" + 각 프리셋의 위치 미리보기 썸네일을 가로로 나열, 현재 항목에 강조색 테두리.

### 4. 컴포넌트 / 파일 구조

- **`Models/CycleHUDStyle.swift`** (신규): `enum CycleHUDStyle: String, Codable, CaseIterable { case off, list, thumbnails }`. `displayName`(한글 라벨) 제공.
- **`Storage/ConfigStore.swift`** (수정): `@Published var cycleHUDStyle: CycleHUDStyle = .thumbnails`. `AppConfig`에 필드 추가, `decodeIfPresent(...) ?? .thumbnails`로 하위호환 디코딩(기존 `deadzones` 추가 방식과 동일). `save()`/`export`/`importConfig`의 `AppConfig` 생성에 포함.
- **`UI/HUD/CycleHUDController.swift`** (신규): `@MainActor final class CycleHUDController`. `static let shared`. 진입점 `func show(cycleName: String, items: [HUDItem], currentIndex: Int, style: CycleHUDStyle)`. 내부에서 NSPanel 생성·재사용, 중앙 배치, 페이드인, 1.2초 디바운스 페이드아웃. `style == .off`면 즉시 return. `HUDItem`은 `struct HUDItem { let name: String; let frame: RelativeFrame }`.
- **`UI/HUD/CycleHUDView.swift`** (신규): SwiftUI 뷰. 입력 = 사이클명, `[HUDItem]`, currentIndex, style. `style`에 따라 목록/썸네일 분기. 어두운 vibrancy 배경 + 밝은 글자, `colorScheme` 다크 고정.
- **`UI/HUD/PresetThumbnail.swift`** (신규): 작은 모니터 비율 박스(예: 56×35)에 `RelativeFrame`을 사각형으로 그리는 비대화식 뷰. 썸네일 스타일 전용.

### 5. 연결 지점

- `HotkeyRegistry.advanceCycle(id:)`: 적용된 사이클의 `name`, 프리셋들의 `(name, frame)`, 선택된 `index`, `store.cycleHUDStyle`를 컨트롤러에 전달. HUD 컨트롤러는 store에 직접 접근하지 않고 인자만 받는다(의존성 명확).

### 6. 엣지 케이스

- 프리셋 0개 사이클: 기존대로 동작 없음 → HUD도 안 뜸(`advanceCycle`이 이미 early-return).
- 멀티 모니터: HUD는 `NSScreen.main` 중앙. 썸네일은 단일 프리셋의 `RelativeFrame`만 그리므로 모니터 구분 불필요.
- 다크/라이트 모드: HUD는 항상 어두운 패널 + 밝은 글자(시스템 HUD 관례). `colorScheme` 다크 고정.

## 범위 밖

- HUD에서 직접 프리셋을 클릭해 선택하는 인터랙션 (HUD는 표시 전용, 클릭 통과).
- 사이클이 아닌 단일 프리셋 적용 시의 HUD.
- HUD 위치/타이밍의 세부 커스터마이즈(고정 1.2초, 중앙).

## 검증

- 빌드 후 앱 자동 재실행(메모리: restart-after-changes).
- 확인: 사이클 핫키 연속 입력 시 HUD가 뜨고 현재 위치 갱신 / 1.2초 후 페이드아웃 / 연속 입력 시 유지 / 설정에서 off·list·thumbnails 전환 동작 / 포커스를 뺏지 않음(클릭 통과) / 프리셋 0개 사이클은 안 뜸.
- 스크린샷 자동 테스트는 하지 않음(메모리: navsplitview-sidebar-glass-card).
