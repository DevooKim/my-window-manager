import Foundation
import Testing
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
