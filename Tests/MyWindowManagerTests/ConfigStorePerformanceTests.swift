import Foundation
import Testing
import Combine
import Carbon.HIToolbox
@testable import MyWindowManager

@MainActor
struct ConfigStorePerformanceTests {
    @Test func loadingExistingConfigurationDoesNotRewriteIt() throws {
        let url = try temporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var config = AppConfig(presets: [], layouts: [], cycles: [], deadzones: [])
        config.sizeStepRatio = 0.2
        let original = try JSONEncoder().encode(config)
        try original.write(to: url)

        _ = ConfigStore(configURL: url)

        #expect(try Data(contentsOf: url) == original)
    }

    @Test func nonRegistrationChangesDoNotPublishHotkeyChanges() throws {
        let url = try temporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConfigStore(configURL: url)
        var events = 0
        let cancellable = store.hotkeyConfigurationDidChange.sink { events += 1 }
        var preset = ResizePreset(name: "Draft", frame: .leftHalf)

        store.upsert(preset: preset)
        preset.name = "Renamed"
        preset.frame = .fullScreen
        store.upsert(preset: preset)
        store.upsert(layout: Layout(name: "Draft Layout", placements: []))
        store.upsert(cycle: PresetCycle(name: "Draft Cycle"))
        store.upsert(deadzone: DisplayDeadzone(displayID: "test", displayName: "Test"))
        store.cycleHUDStyle = .off
        store.snapSettings.edgeTop.toggle()
        store.sizeStepRatio = 0.2

        #expect(events == 0)
        withExtendedLifetime(cancellable) {}
    }

    @Test func registrationChangesPublishOncePerMutation() throws {
        let url = try temporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConfigStore(configURL: url)
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

    @Test func layoutRegistrationChangesPublishOncePerMutation() throws {
        let url = try temporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConfigStore(configURL: url)
        var events = 0
        let cancellable = store.hotkeyConfigurationDidChange.sink { events += 1 }
        let layout = Layout(
            name: "Bound Layout",
            placements: [],
            hotkey: commandHotkey
        )

        store.upsert(layout: layout)
        store.deleteLayout(id: layout.id)

        #expect(events == 2)
        withExtendedLifetime(cancellable) {}
    }

    @Test func cycleRegistrationChangesPublishOncePerMutation() throws {
        let url = try temporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConfigStore(configURL: url)
        var events = 0
        let cancellable = store.hotkeyConfigurationDidChange.sink { events += 1 }
        let cycle = PresetCycle(name: "Bound Cycle", hotkey: commandHotkey)

        store.upsert(cycle: cycle)
        store.deleteCycle(id: cycle.id)

        #expect(events == 2)
        withExtendedLifetime(cancellable) {}
    }

    @Test func moveRegistrationChangesPublishOncePerMutation() throws {
        let url = try temporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConfigStore(configURL: url)
        var events = 0
        let cancellable = store.hotkeyConfigurationDidChange.sink { events += 1 }

        store.moveBindings = [MoveBinding(action: .displayNext, hotkey: commandHotkey)]
        store.moveBindings = []

        #expect(events == 2)
        withExtendedLifetime(cancellable) {}
    }

    @Test func sizeRegistrationChangesPublishOncePerMutation() throws {
        let url = try temporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConfigStore(configURL: url)
        var events = 0
        let cancellable = store.hotkeyConfigurationDidChange.sink { events += 1 }

        store.sizeBindings = [SizeBinding(action: .grow, hotkey: commandHotkey)]
        store.sizeBindings = []

        #expect(events == 2)
        withExtendedLifetime(cancellable) {}
    }

    private var commandHotkey: HotkeyConfig {
        HotkeyConfig(keyCode: 0, modifiers: UInt32(cmdKey))
    }

    private func temporaryConfigURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwm-performance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("config.json")
    }
}
