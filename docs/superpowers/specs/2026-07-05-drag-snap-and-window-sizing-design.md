# 드래그 스냅 + 창 확대/축소 설계

날짜: 2026-07-05
상태: 승인 대기

## 개요

두 기능을 추가한다.

1. **드래그 스냅** — 창을 마우스로 드래그해 디스플레이 가장자리(상하좌우)나
   모서리에 가져가면 자동으로 리사이즈되어 붙는다.
2. **창 확대/축소** — 핫키로 포커스 창을 화면 크기의 일정 비율만큼
   키우거나 줄인다.

구현은 Sonnet 서브에이전트가 수행한다(계획: Fable, 구현: Sonnet).

## 1. 드래그 스냅

### 동작 사양

드래그 중 커서가 화면 가장자리 **8px** 이내에 들어오면 zone이 활성화되고,
마우스를 놓으면 창이 해당 zone의 프레임으로 리사이즈·배치된다.

| 커서 위치 | 결과 (SnapZone) |
|---|---|
| 왼쪽 가장자리 | 왼쪽 절반 `leftHalf` |
| 오른쪽 가장자리 | 오른쪽 절반 `rightHalf` |
| 위쪽 가장자리 | 최대화(placementArea 전체) `maximize` |
| 아래쪽 가장자리 | 아래 절반 `bottomHalf` |
| 모서리 근방 | 해당 1/4 `topLeftQuarter` 등 4종 |

- **코너 판정**: 커서가 어느 가장자리의 threshold 안에 있으면서 그 가장자리의
  끝(모서리)에서 **128px** 이내면 코너 zone. 코너가 엣지보다 우선한다.
  코너는 `corners` 토글로만 제어되며 인접 엣지 토글과 무관하다.
  코너 토글이 꺼져 있으면 커서에서 더 가까운 가장자리의 엣지 규칙으로 폴백.
- **좌표계**: zone 판정은 커서 위치(`NSEvent.mouseLocation`, Cocoa 좌표)와
  `NSScreen.frame`으로 한다. 목표 프레임은
  `ScreenHelper.placementArea(of:)`(AX 좌표, deadzone 반영) 기준으로 계산한다.
- **멀티 디스플레이**: zone은 커서가 속한 화면 기준. 디스플레이 사이 내부
  경계도 threshold 안에 들어오면 동일하게 동작한다.

### 드래그 세션 판정

전역 NSEvent 모니터(`leftMouseDown` / `leftMouseDragged` / `leftMouseUp`) 사용.

1. mouseDown: 커서 위치 기록.
2. 드래그 거리가 4px를 넘으면 시스템 전역 AX hit-test
   (`AXUIElementCopyElementAtPosition`)로 커서 아래 창을 찾는다.
3. 이후 드래그에서 그 창의 `frame.origin`이 mouseDown 시점 대비 움직였으면
   "창 드래그 세션"으로 확정한다(텍스트 선택 등 오탐 배제).
   AX frame 폴링은 50ms 스로틀.
4. 세션 중 zone 진입/이탈에 따라 미리보기 표시/숨김.
5. mouseUp: zone 안이면 스냅 적용(`WindowController.setFrame`).

자기 앱(설정 창)의 이벤트는 전역 모니터에 잡히지 않으므로 스냅 대상이
아니다(의도된 제약).

### 미리보기 오버레이

- 비활성(non-activating)·클릭 통과(`ignoresMouseEvents`) NSPanel.
- 반투명 라운드 사각형으로 스냅될 영역을 표시. 창 레벨은 드래그 중인 창 위.
- zone 변경 시 이동, 이탈 시 숨김. 미리보기 토글이 꺼져 있으면 표시하지 않음
  (스냅 자체는 동작).

### 스냅 해제 시 크기 복원

- `SnapRestoreStore`(인메모리): `CGWindowID`(기존 `_AXUIElementGetWindow`
  활용) → `(preSnapSize, snappedFrame)`.
- 스냅 적용 직전 프레임을 저장한다.
- 저장된 창의 드래그 세션이 시작되고 현재 프레임이 `snappedFrame`과
  일치(~1px)하면, 드래그로 창이 10px 이상 벗어난 시점에 **크기만**
  `preSnapSize`로 복원한다(위치는 커서를 따라감). 엔트리는 제거.
- 현재 프레임이 `snappedFrame`과 다르면(사용자가 수동 리사이즈함) 복원하지
  않고 엔트리만 제거.
- 리스크: 네이티브 드래그 중 리사이즈가 일부 앱에서 글리치날 수 있음.
  글리치가 확인되면 mouseUp 시 복원으로 폴백(구현 단계 결정 포인트).

### 설정 (각 항목 on/off)

`SnapSettings` 구조체, 모든 필드 기본값 `true`:

```swift
struct SnapSettings: Codable, Hashable {
    var enabled: Bool = true          // 마스터
    var edgeLeft: Bool = true         // 왼쪽 절반
    var edgeRight: Bool = true        // 오른쪽 절반
    var edgeTop: Bool = true          // 최대화
    var edgeBottom: Bool = true       // 아래 절반
    var corners: Bool = true          // 쿼터 스냅
    var preview: Bool = true          // 미리보기 오버레이
    var restoreOnUnsnap: Bool = true  // 해제 시 크기 복원
}
```

- 꺼진 zone은 미리보기도 뜨지 않고 스냅도 되지 않는다.
- 마스터가 꺼지면 모니터 자체를 중지한다.

### 컴포넌트 (`Features/Snap/`)

| 파일 | 역할 |
|---|---|
| `DragSnapMonitor.swift` | 전역 마우스 모니터, 드래그 세션 상태 머신, 적용 |
| `SnapZoneResolver.swift` | 순수 함수: (커서, 화면, 설정) → zone → 목표 프레임 |
| `SnapPreviewOverlay.swift` | 미리보기 패널 컨트롤러 |
| `SnapRestoreStore.swift` | windowID → 복원 정보 (인메모리) |

라이프사이클: `AppState`에서 `DragSnapMonitor`를 생성하고
`ConfigStore.snapSettings`를 구독해 start/stop. 접근성 권한이 없으면 시작하지
않고, 권한 획득 후(기존 `AccessibilityManager` 흐름) 시작한다.

### 시스템 타일링과의 공존

macOS 15+(Tahoe 포함)는 자체 드래그 타일링이 있어 미리보기가 이중으로 뜰 수
있다. 스냅 탭 footer에 "시스템 설정 > 데스크탑 및 Dock > 창 타일링"을 끄라는
안내 문구를 넣는다. 자동 감지/비활성화는 하지 않는다(YAGNI).

## 2. 창 확대/축소

### 동작 사양

- 고정 액션 2종: `SizeAction.grow` / `.shrink` + `SizeBinding`(핫키) —
  `MoveAction`/`MoveBinding`과 동일 패턴.
- 한 번 누르면 창이 속한 화면의 `placementArea` 크기의 **N%**(기본 10%,
  설정 범위 2~30%)만큼 폭과 높이를 증감한다.
- **앵커**: 창 중심 고정. 사방으로 균등하게 커지고 작아진다.
- **클램프**: 확대 시 `placementArea`를 넘으면 크기는 area까지, 위치는
  안쪽으로 밀어 넣는다. 축소 시 최소 크기 **200×150px** 하한(앱 자체 AX
  최소 크기가 더 크면 AX가 알아서 막는다).
- 핫키 핸들러는 다른 액션과 동일하게 `resetCycleState()`를 호출한다.

계산(의사코드):

```
area = placementArea(screen(containing: win))
dW = area.width * step, dH = area.height * step   // shrink는 음수
newW = clamp(w + dW, 200, area.width)
newH = clamp(h + dH, 150, area.height)
newX = clamp(midX - newW/2, area.minX, area.maxX - newW)
newY = clamp(midY - newH/2, area.minY, area.maxY - newH)
```

### 컴포넌트

- `Features/Resize/WindowSizer.swift` — `step(_ action:, ratio:)` 적용 +
  순수 계산 함수 분리(테스트용).
- `Models/SizeAction.swift` — enum + `SizeBinding`.

## 3. 저장 모델 변경

`AppConfig`에 추가(모두 `decodeIfPresent` + 기본값 — 기존 config 하위호환):

- `snapSettings: SnapSettings` (기본값 전부 on)
- `sizeBindings: [SizeBinding]` (기본 `[]`)
- `sizeStepRatio: Double` (기본 `0.1`)
- `version`을 3으로 올림 (informational)

`ConfigStore`:

- `@Published` 3종 추가, `didSet`에서 `save()`.
- export/import에 포함.
- `hotkeyConflicts(for:excludingId:)`에 `sizeBindings` 반영 — 이동 바인딩과
  같은 방식(UUID가 없으므로 같은 combo가 move+size 통틀어 2개 이상일 때
  서로 충돌로 표시).

## 4. 설정 UI

- `EditorTab`에 `snap` 케이스 신설 — 라벨 "스냅", 심볼
  `rectangle.leadinghalf.inset.filled`, 틴트 `.pink`. `move` 탭 라벨은
  "이동·크기"로 변경.
- **SnapView** (신설, `.formStyle(.grouped)`):
  - Section "드래그 스냅": 마스터 토글.
  - Section "가장자리": 왼쪽/오른쪽/위(최대화)/아래 토글 4개.
  - Section "부가 동작": 코너 쿼터, 미리보기, 해제 시 크기 복원 토글.
  - footer: 시스템 창 타일링 끄기 안내.
  - 마스터 off 시 하위 토글 `disabled`.
- **MoveView** 확장: Section "창 크기" — 확대 row, 축소 row(기존 row 패턴
  재사용), 스텝 비율 컨트롤(%, 2~30, 기본 10).

## 5. 테스트

- 테스트 타깃이 없으므로 `Tests/MyWindowManagerTests` 신설
  (swift-tools 5.5+는 executable 타깃 테스트 가능).
  - `SnapZoneResolverTests` — 엣지/코너 판정, 토글 off 폴백, 멀티 디스플레이
    경계, deadzone 반영 프레임.
  - `WindowSizerTests` — 증감 계산, 경계 클램프, 최소 크기, 중심 앵커.
- AX·이벤트 모니터가 얽힌 부분은 수동 검증: `docs/smoke-test.md`에 시나리오
  추가(엣지 4방향, 코너 4방향, 미리보기, 복원, 토글 off, 멀티 디스플레이,
  확대/축소 클램프).

## 6. 범위 제외 (YAGNI)

- 수정자 키로 스냅 일시 비활성 (사용자가 선택하지 않음)
- 시스템 타일링 자동 감지/끄기
- 스냅 threshold·코너 크기의 사용자 설정 노출 (상수로 시작)
- 핫키 기반 스냅 액션 (스냅은 드래그 전용; 반쪽 배치는 기존 프리셋으로 가능)
