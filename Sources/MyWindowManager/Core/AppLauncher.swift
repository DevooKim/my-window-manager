import AppKit
import ApplicationServices

enum AppLauncher {
    static func ensureLaunched(_ bundleId: String) async {
        if NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleId).first != nil {
            return
        }
        guard let url = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleId) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = false
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    static func waitForWindow(
        bundleId: String, timeout: TimeInterval = 3.0
    ) async -> AXUIElement? {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if let win = WindowController.firstWindow(of: bundleId) {
                try? await Task.sleep(nanoseconds: 250_000_000)
                return win
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return nil
    }
}
