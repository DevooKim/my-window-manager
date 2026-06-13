import SwiftUI
import AppKit

struct MenuBarContent: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var ax: AccessibilityManager
    @EnvironmentObject var app: AppState
    @EnvironmentObject var hotkeys: HotkeyRegistryHolder
    @Environment(\.openWindow) private var openWindow

    // Cap how many of each kind show in the menu bar so it stays compact;
    // the full lists remain available in their editors.
    private let maxLayouts = 3
    private let maxCycles = 3
    private let maxPresets = 5

    var body: some View {
        Group {
            // AppKit 경로(hotkey 등)에서도 설정 창을 열 수 있도록 SwiftUI의
            // openWindow 액션을 AppState에 주입해 둔다.
            Color.clear.frame(width: 0, height: 0)
                .onAppear {
                    app.openEditorWindow = { openWindow(id: AppState.editorWindowID) }
                    app.openUpdateWindow = { openWindow(id: UpdatePromptState.windowID) }
                    app.openAboutWindow = { openWindow(id: AppState.aboutWindowID) }
                }

            Button("My Window Manager 정보") {
                app.openAboutWindow?()
                NSApp.activate(ignoringOtherApps: true)
            }

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
                app.selectedTab = .presets
                openWindow(id: AppState.editorWindowID)
                NSApp.activate(ignoringOtherApps: true)
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


    private func menuTitle(_ name: String, hotkey: HotkeyConfig?) -> String {
        if let h = hotkey { return "\(name)   \(h.displayString)" }
        return name
    }
}
