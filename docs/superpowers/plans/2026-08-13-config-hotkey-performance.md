# Config and Hotkey Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent read-only configuration loads from writing to disk and rebuild global hotkeys only when their registered targets or key combinations change.

**Architecture:** `ConfigStore` batches full-configuration replacement, compares a narrow registration snapshot, and publishes one dedicated change signal. `HotkeyRegistry` owns the subscription to that signal; app and editor views no longer call or schedule broad registry rebuilds.

**Tech Stack:** Swift 6 package, AppKit, Combine, Swift Testing

---

### Task 1: Make configuration loading read-only

**Files:**
- Modify: `Sources/MyWindowManager/Storage/ConfigStore.swift`
- Create: `Tests/MyWindowManagerTests/ConfigStorePerformanceTests.swift`

- [ ] **Step 1: Write the failing load test**

```swift
import Testing
import Foundation
import Combine
import Carbon.HIToolbox
@testable import MyWindowManager

@MainActor
struct ConfigStorePerformanceTests {
    private func temporaryConfigURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwm-performance-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("config.json")
    }

@Test func loadingExistingConfigurationDoesNotRewriteIt() throws {
    let url = temporaryConfigURL()
    var config = AppConfig(presets: [], layouts: [], cycles: [], deadzones: [])
    config.sizeStepRatio = 0.2
    let original = try JSONEncoder().encode(config)
    try original.write(to: url)

    _ = ConfigStore(configURL: url)

    #expect(try Data(contentsOf: url) == original)
}
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `make test`

Expected: FAIL because the compact input is rewritten by `sizeStepRatio.didSet` using pretty-printed, sorted JSON.

- [ ] **Step 3: Suppress automatic persistence while loading**

Add an `isApplyingConfiguration` guard to automatically persisted properties and set it while `load()` assigns decoded/default values:

```swift
private var isApplyingConfiguration = false

@Published var sizeStepRatio: Double = 0.1 {
    didSet {
        if !isApplyingConfiguration, sizeStepRatio != oldValue { save() }
    }
}

func load() {
    isApplyingConfiguration = true
    defer { isApplyingConfiguration = false }
    if let data = try? Data(contentsOf: url),
       let config = try? JSONDecoder().decode(AppConfig.self, from: data) {
        presets = config.presets
        layouts = config.layouts
        cycles = config.cycles
        deadzones = config.deadzones
        cycleHUDStyle = config.cycleHUDStyle
        moveBindings = config.moveBindings
        snapSettings = config.snapSettings
        sizeBindings = config.sizeBindings
        sizeStepRatio = config.sizeStepRatio
        needsSetup = false
    } else {
        presets = []
        layouts = []
        cycles = []
        deadzones = []
        moveBindings = []
        snapSettings = SnapSettings()
        sizeBindings = []
        sizeStepRatio = 0.1
        needsSetup = true
    }
    syncDeadzones()
}
```

Apply the same guard to `cycleHUDStyle`, `moveBindings`, `snapSettings`, and `sizeBindings`.

- [ ] **Step 4: Run the focused and full tests**

Run: `make test`

Expected: PASS.

Run: `make test`

Expected: all baseline and new tests pass.

- [ ] **Step 5: Commit the load optimization**

```bash
git add Sources/MyWindowManager/Storage/ConfigStore.swift Tests/MyWindowManagerTests/ConfigStorePerformanceTests.swift
git commit -m "perf: 설정 로드 중 불필요한 저장 제거"
```

### Task 2: Publish only effective hotkey-registration changes

**Files:**
- Modify: `Sources/MyWindowManager/Storage/ConfigStore.swift`
- Modify: `Tests/MyWindowManagerTests/ConfigStorePerformanceTests.swift`

- [ ] **Step 1: Write failing signal tests**

```swift
@Test func nonRegistrationChangesDoNotPublishHotkeyChanges() {
    let store = ConfigStore(configURL: temporaryConfigURL())
    var events = 0
    let cancellable = store.hotkeyConfigurationDidChange.sink { events += 1 }
    let preset = ResizePreset(name: "Draft", frame: .leftHalf)

    store.upsert(preset: preset)
    store.snapSettings.edgeTop.toggle()
    store.sizeStepRatio = 0.2

    #expect(events == 0)
    withExtendedLifetime(cancellable) {}
}

@Test func registrationChangesPublishOncePerMutation() {
    let store = ConfigStore(configURL: temporaryConfigURL())
    var events = 0
    let cancellable = store.hotkeyConfigurationDidChange.sink { events += 1 }
    var preset = ResizePreset(name: "Bound", frame: .leftHalf)
    preset.hotkey = HotkeyConfig(keyCode: 0, modifiers: UInt32(cmdKey))

    store.upsert(preset: preset)
    preset.name = "Renamed"
    store.upsert(preset: preset)
    store.deletePreset(id: preset.id)

    #expect(events == 2)
    withExtendedLifetime(cancellable) {}
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `make test`

Expected: build failure because `hotkeyConfigurationDidChange` does not exist.

- [ ] **Step 3: Add a narrow registration snapshot and publisher**

Add `PassthroughSubject<Void, Never>` and compare compact registration entries containing only item identity/action plus non-nil `HotkeyConfig`:

```swift
let hotkeyConfigurationDidChange = PassthroughSubject<Void, Never>()

private struct ItemRegistration: Equatable {
    let id: UUID
    let hotkey: HotkeyConfig
}

private struct FixedRegistration: Equatable {
    let action: String
    let hotkey: HotkeyConfig
}

private struct HotkeyRegistrationState: Equatable {
    let presets: [ItemRegistration]
    let layouts: [ItemRegistration]
    let cycles: [ItemRegistration]
    let moves: [FixedRegistration]
    let sizes: [FixedRegistration]
}
```

Each relevant property `didSet` compares its old and new registration entries and sends only when they differ. Non-registration properties retain persistence behavior without sending.

- [ ] **Step 4: Run focused and full tests**

Run: `make test`

Expected: all performance tests pass.

Run: `make test`

Expected: all tests pass.

- [ ] **Step 5: Commit targeted invalidation**

```bash
git add Sources/MyWindowManager/Storage/ConfigStore.swift Tests/MyWindowManagerTests/ConfigStorePerformanceTests.swift
git commit -m "perf: 실제 핫키 변경만 갱신 신호 전송"
```

### Task 3: Batch imports and centralize registry ownership

**Files:**
- Modify: `Sources/MyWindowManager/Storage/ConfigStore.swift`
- Modify: `Sources/MyWindowManager/Hotkey/HotkeyRegistry.swift`
- Modify: `Sources/MyWindowManager/App/MyWindowManagerApp.swift`
- Modify: `Sources/MyWindowManager/UI/Editor/GeneralView.swift`
- Modify: `Sources/MyWindowManager/UI/Editor/MoveView.swift`
- Modify: `Sources/MyWindowManager/UI/Editor/PresetEditorView.swift`
- Modify: `Sources/MyWindowManager/UI/Editor/CycleEditorView.swift`
- Modify: `Sources/MyWindowManager/UI/Editor/LayoutEditorView.swift`
- Modify: `Tests/MyWindowManagerTests/ConfigStorePerformanceTests.swift`

- [ ] **Step 1: Write failing batch-import tests**

```swift
@Test func importPersistsConfigurationOnce() throws {
    let target = temporaryConfigURL()
    let source = temporaryConfigURL()
    try encodedImportedConfig().write(to: source)
    var writes = 0
    let store = ConfigStore(configURL: target) { data, url in
        writes += 1
        try data.write(to: url, options: .atomic)
    }

    try store.importConfig(from: source)

    #expect(writes == 1)
}

@Test func importPublishesOneHotkeyChange() throws {
    let source = temporaryConfigURL()
    try encodedImportedConfig().write(to: source)
    let store = ConfigStore(configURL: temporaryConfigURL())
    var events = 0
    let cancellable = store.hotkeyConfigurationDidChange.sink { events += 1 }

    try store.importConfig(from: source)

    #expect(events == 1)
    withExtendedLifetime(cancellable) {}
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `make test`

Expected: build failure because the injectable persistence closure is not supported, then an event-count failure until import batching is implemented.

- [ ] **Step 3: Batch full replacements and inject internal persistence**

Add a production-default persistence closure and a batching helper:

```swift
private let writeConfiguration: (Data, URL) throws -> Void

init(
    configURL: URL,
    writeConfiguration: @escaping (Data, URL) throws -> Void = {
        try $0.write(to: $1, options: .atomic)
    }
) {
    self.url = configURL
    self.writeConfiguration = writeConfiguration
    load()
}

private func applyAsBatch(_ updates: () -> Void) {
    let oldRegistrations = hotkeyRegistrationState
    isApplyingConfiguration = true
    updates()
    isApplyingConfiguration = false
    syncDeadzones()
    if oldRegistrations != hotkeyRegistrationState {
        hotkeyConfigurationDidChange.send()
    }
}
```

Use the helper in `load()`, `importConfig(from:)`, and `applyStarterScheme(_:)`. Call `save()` once after import/starter application and make `save()` use `writeConfiguration`.

- [ ] **Step 4: Make the registry own its subscription**

In `HotkeyRegistry`, retain an `AnyCancellable` and subscribe during `bind(store:)`:

```swift
private var hotkeyConfigurationCancellable: AnyCancellable?

func bind(store: ConfigStore) {
    self.store = store
    hotkeyConfigurationCancellable = store.hotkeyConfigurationDidChange
        .sink { [weak self] in self?.rebuild() }
    rebuild()
}
```

The focused `ConfigStore` tests prove the signal contract; the existing `HotkeyRegistryRaycastTests` continue to cover store binding and cycle execution while this compile-time integration moves subscription ownership into the registry.

- [ ] **Step 5: Remove duplicate callers**

Delete the `store.objectWillChange` subscription from `AppDelegate` and remove editor/import calls to `hotkeys.registry.rebuild()`. Remove now-unused environment objects and imports only where the compiler proves they are unused.

- [ ] **Step 6: Verify batching, ownership, and regressions**

Run: `make test`

Expected: all performance tests pass.

Run: `make test`

Expected: all tests pass with no warnings.

Run: `rg -n "objectWillChange|registry\\.rebuild\\(\\)" Sources/MyWindowManager/App Sources/MyWindowManager/UI/Editor`

Expected: no broad app subscription or editor-owned registry rebuild remains.

- [ ] **Step 7: Commit the batched integration**

```bash
git add Sources/MyWindowManager Tests/MyWindowManagerTests
git commit -m "perf: 설정 가져오기와 핫키 갱신 일괄 처리"
```

### Task 4: Final verification and PR preparation

**Files:**
- Verify only: all intended source, test, spec, and plan files

- [ ] **Step 1: Run final checks**

Run: `make test`

Expected: all tests pass.

Run: `swift build -c release`

Expected: release build succeeds without new warnings.

Run: `git diff --check origin/main...HEAD`

Expected: no whitespace errors.

- [ ] **Step 2: Audit scope**

Run: `git status -sb && git diff --stat origin/main...HEAD && git diff origin/main...HEAD`

Expected: only the performance spec/plan, focused source files, and tests appear; pre-existing untracked files remain unstaged.

- [ ] **Step 3: Request independent code review**

Review `origin/main...HEAD` against `docs/superpowers/specs/2026-08-13-config-hotkey-performance-design.md`. Fix every Critical or Important finding and rerun the relevant checks.

- [ ] **Step 4: Push and open a Draft PR**

```bash
git push -u origin agent/optimize-config-hotkey-updates
gh pr create --draft --base main --head agent/optimize-config-hotkey-updates --title "perf: 설정 저장 및 핫키 갱신 최적화" --body-file /tmp/my-window-manager-performance-pr.md
```

Expected: a Draft PR targeting `main` with the motivation, behavior impact, and exact validation results.
