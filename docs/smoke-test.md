# My Window Manager Manual Smoke Test

Run `make run` (or `open "dist/My Window Manager.app"`). The bundle is signed
with the stable "MyWindowManager Dev" identity, so the Accessibility grant
persists across rebuilds. If it ever gets lost: System Settings > Privacy &
Security > Accessibility — remove and re-add My Window Manager.

## First-run / permission
- [ ] On first launch (no Accessibility grant or no config), the onboarding
      window appears and macOS prompts for Accessibility access.
- [ ] The onboarding/permission view shows the app icon and an Accessibility
      status row.
- [ ] Granting permission in System Settings flips the status to ✓ and the
      hotkeys start working without a manual relaunch.
- [ ] 8 default resize presets are loaded with ⌃⌥ hotkeys.

## Menu bar
- [ ] No Dock icon appears (LSUIElement).
- [ ] Menu bar icon shows; menu contains the preset/cycle/layout sections,
      "설정...", "My Window Manager 정보", "업데이트 확인...", "재시작", "종료".
- [ ] "My Window Manager 정보" opens the standard About panel (icon, version,
      © 2026 DevooKim, GitHub link).
- [ ] "종료" terminates the app; "재시작" relaunches it.

## Resize presets
- [ ] Triggering a preset (menu or hotkey) snaps the front window to the saved
      rectangle on the screen under the cursor.
- [ ] Mixed ratio + px presets (e.g. "Left half + height 200px") apply both
      dimensions correctly.
- [ ] Editing a preset in the editor and re-triggering reflects the change.

## Cycles
- [ ] Triggering a cycle (menu or hotkey) advances the front window through
      the cycle's presets, wrapping at the end.

## Layouts
- [ ] Triggering a layout places every configured app/window in one batch.
- [ ] A layout that targets a not-running app auto-launches it, then places it.
- [ ] Multi-monitor layouts place windows on the correct displays.

## Visual editor
- [ ] Preset/Layout editors open from the menu bar.
- [ ] Dragging on the monitor canvas draws a region; numeric inputs fine-tune it.
- [ ] Per-dimension unit toggle (ratio/px) works.
- [ ] Recording a new hotkey works and persists across relaunch.

## Config backup
- [ ] 설정 → "내보내기..." writes a JSON file with all presets/cycles/layouts.
- [ ] "가져오기..." overwrites the current config and rebuilds hotkeys live.
- [ ] Config lives at
      `~/Library/Application Support/MyWindowManager/config.json`.

## Auto-update
- [ ] "업데이트 확인..." (menu bar or 설정 tab) reports "최신 버전입니다" when up
      to date.
- [ ] To test the update path: lower the dist bundle's
      `CFBundleShortVersionString`, re-sign
      (`codesign --force --deep --sign "MyWindowManager Dev" "dist/My Window Manager.app"`),
      relaunch → "업데이트 확인" detects the newer GitHub release, downloads,
      de-quarantines, swaps the bundle in place, and relaunches. Restore with
      `make app`.

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
