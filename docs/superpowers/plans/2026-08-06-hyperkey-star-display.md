# Hyperkey Star Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display an exact Control-Option-Shift-Command Hyperkey modifier set as `✦` while preserving all other shortcut displays.

**Architecture:** Keep the behavior in `HotkeyConfig.displayString`, the existing shared formatter used throughout the app. Compare the Carbon modifier mask with the exact four-modifier mask before appending the unchanged key description.

**Tech Stack:** Swift 6 package, AppKit/Carbon modifier flags, Swift Testing

---

### Task 1: Hyperkey display formatting

**Files:**
- Create: `Tests/MyWindowManagerTests/HotkeyConfigTests.swift`
- Modify: `Sources/MyWindowManager/Models/HotkeyConfig.swift`

- [x] **Step 1: Write the failing tests**

```swift
import Testing
import Carbon.HIToolbox
@testable import MyWindowManager

@Test func hyperkeyUsesSparkleSymbol() {
    let modifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)
    let hotkey = HotkeyConfig(keyCode: 0, modifiers: modifiers)
    #expect(hotkey.displayString == "✦A")
}

@Test func regularModifiersKeepExistingSymbols() {
    let modifiers = UInt32(controlKey | optionKey)
    let hotkey = HotkeyConfig(keyCode: 0, modifiers: modifiers)
    #expect(hotkey.displayString == "⌃⌥A")
}
```

- [x] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter HotkeyConfigTests`

Expected: `hyperkeyUsesSparkleSymbol` fails because the current value is `⌃⌥⇧⌘A`; the regular-modifier test passes.

- [x] **Step 3: Implement the exact-mask formatter**

```swift
let hyperkeyModifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)
if modifiers == hyperkeyModifiers {
    s = "✦"
} else {
    if m.contains(.control) { s += "⌃" }
    if m.contains(.option) { s += "⌥" }
    if m.contains(.shift) { s += "⇧" }
    if m.contains(.command) { s += "⌘" }
}
```

- [x] **Step 4: Verify GREEN and regressions**

Run: `swift test --filter HotkeyConfigTests`

Expected: both focused tests pass.

Run: `swift test`

Expected: the full test suite passes.

- [x] **Step 5: Commit the implementation**

```bash
git add Tests/MyWindowManagerTests/HotkeyConfigTests.swift Sources/MyWindowManager/Models/HotkeyConfig.swift docs/superpowers/plans/2026-08-06-hyperkey-star-display.md
git commit -m "feat: Hyperkey 조합을 별 아이콘으로 표시"
```
