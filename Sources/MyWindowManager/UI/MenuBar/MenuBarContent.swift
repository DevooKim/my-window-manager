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
            Button("My Window Manager 정보") { showAbout() }

            Divider()

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

            Button("업데이트 확인...") { Updater.checkForUpdates(silent: false) }
            Button {
                app.openEditor(.presets)
            } label: {
                Label("설정...", systemImage: "gearshape")
            }
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("종료", systemImage: "power")
            }
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

    private func menuTitle(_ name: String, hotkey: HotkeyConfig?) -> String {
        if let h = hotkey { return "\(name)   \(h.displayString)" }
        return name
    }
}
