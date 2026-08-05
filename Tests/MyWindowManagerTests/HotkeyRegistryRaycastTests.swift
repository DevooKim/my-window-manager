import Testing
import Foundation
import ApplicationServices
@testable import MyWindowManager

@MainActor
struct HotkeyRegistryRaycastTests {
    @Test func unboundCycleRegistryReportsFailure() {
        let registry = HotkeyRegistry()
        #expect(!registry.advanceCycle(id: UUID()))
    }

    @Test func failedApplyDoesNotAdvanceCycleOrShowHUD() {
        let first = ResizePreset(name: "First", frame: .leftHalf, hotkey: nil)
        let second = ResizePreset(name: "Second", frame: .fullScreen, hotkey: nil)
        let cycle = PresetCycle(
            name: "Test Cycle",
            presetIds: [first.id, second.id],
            hotkey: nil
        )
        let configURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mwm-raycast-\(UUID().uuidString).json")
        let store = ConfigStore(configURL: configURL)
        store.presets = [first, second]
        store.cycles = [cycle]

        var attempts: [UUID] = []
        var results = [true, false, true]
        var shownIndexes: [Int] = []
        let registry = HotkeyRegistry(
            applyPreset: { preset, _ in
                attempts.append(preset.id)
                return results.removeFirst()
            },
            showCycleHUD: { _, _, index, _ in shownIndexes.append(index) }
        )
        registry.bind(store: store)
        let window = AXUIElementCreateSystemWide()

        #expect(registry.advanceCycle(id: cycle.id, window: window))
        #expect(!registry.advanceCycle(id: cycle.id, window: window))
        #expect(registry.advanceCycle(id: cycle.id, window: window))
        #expect(attempts == [first.id, second.id, second.id])
        #expect(shownIndexes == [0, 1])
    }
}
