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
            // openWindow 액션 주입은 MenuBarExtra label의 WindowOpenerInjector가
            // 담당한다(메뉴를 열지 않아도, 아이콘이 숨겨져도 동작하도록).

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

            let moves = store.moveBindings.filter { $0.hotkey != nil }
            if !moves.isEmpty {
                Divider()
                Section("이동") {
                    ForEach(moves) { binding in
                        Button(menuTitle(binding.action.label, hotkey: binding.hotkey)) {
                            if binding.action.isSpace {
                                SpaceMover.move(direction: binding.action.direction)
                            } else {
                                DisplayMover.move(direction: binding.action.direction)
                            }
                        }
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
            .keyboardShortcut(",", modifiers: .command)
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
