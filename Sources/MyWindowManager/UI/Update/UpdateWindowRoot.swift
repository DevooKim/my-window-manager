import SwiftUI

/// Root view for the SwiftUI update window scene. Renders the current prompt
/// and closes the window once the user resolves it.
struct UpdateWindowRoot: View {
    @EnvironmentObject var state: UpdatePromptState
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if let prompt = state.prompt {
                UpdatePromptView(kind: prompt.kind, notes: prompt.notes) { action in
                    state.resolve(action)
                }
            } else {
                // No active prompt — keep the window empty and dismiss it.
                Color.clear
                    .frame(width: 1, height: 1)
            }
        }
        .onChange(of: state.prompt == nil) { _, isEmpty in
            if isEmpty { dismissWindow(id: UpdatePromptState.windowID) }
        }
    }
}
