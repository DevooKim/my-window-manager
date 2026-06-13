import AppKit
import ApplicationServices

enum LayoutApplier {
    static func apply(_ layout: Layout) async {
        var claimed: [AXUIElement] = []

        for p in layout.placements {
            await launch(p)

            // Wait for a window that hasn't been claimed yet
            guard let win = await waitForUnclaimedWindow(
                bundleId: p.bundleId, excluding: claimed
            ) else { continue }

            claimed.append(win)

            guard let screen = ScreenHelper.resolve(p.displayMatcher) else { continue }
            let area = ScreenHelper.axVisibleFrame(of: screen)
            let frame = p.frame.resolve(in: area)
            await MainActor.run {
                WindowController.setFrame(win, frame: frame)
            }
        }
    }

    // MARK: - Launch with target

    private static func launch(_ p: AppPlacement) async {
        guard let appURL = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: p.bundleId) else { return }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.createsNewApplicationInstance = false

        switch p.target {
        case .none:
            // Launch app if not running; if running, do nothing special
            let already = NSRunningApplication
                .runningApplications(withBundleIdentifier: p.bundleId).first != nil
            if !already && p.launchIfNeeded {
                _ = try? await NSWorkspace.shared.openApplication(
                    at: appURL, configuration: config
                )
            }

        case .path(let path):
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            _ = try? await NSWorkspace.shared.open(
                [url], withApplicationAt: appURL, configuration: config
            )

        case .url(let urlString):
            guard let url = URL(string: urlString) else { return }
            _ = try? await NSWorkspace.shared.open(
                [url], withApplicationAt: appURL, configuration: config
            )
        }
    }

    // MARK: - Window claim helpers

    private static func waitForUnclaimedWindow(
        bundleId: String, excluding claimed: [AXUIElement],
        timeout: TimeInterval = 4.0
    ) async -> AXUIElement? {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if let win = unclaimedWindow(bundleId: bundleId, excluding: claimed) {
                try? await Task.sleep(nanoseconds: 250_000_000)
                // Re-fetch in case window was still appearing
                return unclaimedWindow(bundleId: bundleId, excluding: claimed) ?? win
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return nil
    }

    private static func unclaimedWindow(
        bundleId: String, excluding claimed: [AXUIElement]
    ) -> AXUIElement? {
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleId).first
        else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref)
        guard let arr = ref as? [AXUIElement] else { return nil }

        // Prefer windows not already claimed and not minimized
        for w in arr {
            if claimed.contains(where: { CFEqual($0, w) }) { continue }
            if isMinimized(w) { continue }
            return w
        }
        // Fall back to any unclaimed window
        for w in arr where !claimed.contains(where: { CFEqual($0, w) }) {
            return w
        }
        return nil
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &ref)
        return (ref as? Bool) ?? false
    }
}
