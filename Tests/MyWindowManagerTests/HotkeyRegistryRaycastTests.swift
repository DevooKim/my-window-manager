import Testing
import Foundation
import ApplicationServices
import Carbon.HIToolbox
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

    @Test func boundRegistryTracksStoreHotkeyChanges() throws {
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwm-registry-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: configURL) }
        let store = ConfigStore(configURL: configURL)
        let registry = HotkeyRegistry()
        registry.bind(store: store)
        var preset = ResizePreset(name: "Bound", frame: .leftHalf)
        preset.hotkey = HotkeyConfig(keyCode: 0, modifiers: UInt32(cmdKey))

        #expect(registry.registeredHotkeyCount == 0)
        store.upsert(preset: preset)
        #expect(registry.registeredHotkeyCount == 1)
        store.deletePreset(id: preset.id)
        #expect(registry.registeredHotkeyCount == 0)
    }
}
