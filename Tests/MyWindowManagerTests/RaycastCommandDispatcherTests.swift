import Testing
import Foundation
@testable import MyWindowManager

@MainActor
struct RaycastCommandDispatcherTests {
    @Test func resolvesStoredPresetCycleAndLayout() throws {
        let preset = ResizePreset(name: "Max", frame: .leftHalf)
        let cycle = PresetCycle(name: "Halves", presetIds: [preset.id])
        let layout = Layout(name: "Work", placements: [])

        #expect(try RaycastCommandDispatcher.resolve(
            .preset(preset.id), presets: [preset], cycles: [cycle], layouts: [layout]
        ) == .preset(preset))
        #expect(try RaycastCommandDispatcher.resolve(
            .cycle(cycle.id), presets: [preset], cycles: [cycle], layouts: [layout]
        ) == .cycle(cycle))
        #expect(try RaycastCommandDispatcher.resolve(
            .layout(layout.id), presets: [preset], cycles: [cycle], layouts: [layout]
        ) == .layout(layout))
    }

    @Test func resolvesFixedActionsWithoutConfiguration() throws {
        #expect(try RaycastCommandDispatcher.resolve(
            .move(.displayNext), presets: [], cycles: [], layouts: []
        ) == .move(.displayNext))
        #expect(try RaycastCommandDispatcher.resolve(
            .size(.shrink), presets: [], cycles: [], layouts: []
        ) == .size(.shrink))
    }

    @Test func rejectsDeletedItem() {
        #expect(throws: RaycastCommandDispatcher.DispatchError.self) {
            try RaycastCommandDispatcher.resolve(
                .preset(UUID()), presets: [], cycles: [], layouts: []
            )
        }
    }
}
