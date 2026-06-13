import SwiftUI

/// Invisible helper that captures SwiftUI's `openWindow` action and injects it
/// into `AppState`, so AppKit-side callers (the reopen handler, hotkeys) can
/// open the SwiftUI settings window even when the menu bar menu was never
/// opened. Placed in the MenuBarExtra `label`, which SwiftUI evaluates even
/// while the icon is hidden — unlike the menu content, which only renders when
/// the user clicks the menu.
struct WindowOpenerInjector: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                app.openEditorWindow = { openWindow(id: AppState.editorWindowID) }
                app.openUpdateWindow = { openWindow(id: UpdatePromptState.windowID) }
                app.openAboutWindow = { openWindow(id: AppState.aboutWindowID) }
            }
    }
}
