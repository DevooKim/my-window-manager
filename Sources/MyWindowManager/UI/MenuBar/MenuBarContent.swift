import SwiftUI
import AppKit

struct MenuBarContent: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var ax: AccessibilityManager
    @EnvironmentObject var app: AppState
    @EnvironmentObject var hotkeys: HotkeyRegistryHolder

    // Cap how many of each kind show in the menu bar so it stays compact;
    // the full lists remain available in their editors.
    private let maxLayouts = 3
    private let maxCycles = 3
    private let maxPresets = 5

    var body: some View {
        Group {
            if !ax.isTrusted {
                Button("Accessibility 권한 설정...") {
                    app.openOnboarding()
                }
                Divider()
            }

            if !store.layouts.isEmpty {
                Section("Layouts") {
                    ForEach(store.layouts.prefix(maxLayouts)) { layout in
                        Button(menuTitle(layout.name, hotkey: layout.hotkey)) {
                            Task { await LayoutApplier.apply(layout) }
                        }
                    }
                }
                Divider()
            }

            if !store.cycles.isEmpty {
                Section("Cycles") {
                    ForEach(store.cycles.prefix(maxCycles)) { cycle in
                        Button(menuTitle(cycle.name, hotkey: cycle.hotkey)) {
                            hotkeys.registry.advanceCycle(id: cycle.id)
                        }
                    }
                }
                Divider()
            }

            Section("Resize Presets") {
                ForEach(store.presets.prefix(maxPresets)) { preset in
                    Button(menuTitle(preset.name, hotkey: preset.hotkey)) {
                        _ = ResizeApplier.apply(preset)
                    }
                }
            }

            Divider()

            Button("프리셋 편집...") { app.openPresetEditor() }
            Button("사이클 편집...") { app.openEditor(.cycles) }
            Button("레이아웃 편집...") { app.openLayoutEditor() }
            Button("설정...") { app.openEditor(.info) }

            Divider()

            Button("My Window Manager 정보") { showAbout() }
            Button("업데이트 확인...") { Updater.checkForUpdates(silent: false) }

            Divider()

            Button("재시작") { relaunch() }
            Button("종료") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    /// Standard About panel: bundle icon, name, version, and copyright
    /// come from Info.plist; credits add the GitHub link.
    private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSMutableAttributedString(string: "github.com/DevooKim/my-window-manager")
        credits.addAttribute(
            .link,
            value: "https://github.com/DevooKim/my-window-manager",
            range: NSRange(location: 0, length: credits.length)
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private func relaunch() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", url.path]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func menuTitle(_ name: String, hotkey: HotkeyConfig?) -> String {
        if let h = hotkey { return "\(name)   \(h.displayString)" }
        return name
    }
}
