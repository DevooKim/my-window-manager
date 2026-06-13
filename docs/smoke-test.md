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
