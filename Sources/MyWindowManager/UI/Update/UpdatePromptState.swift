import SwiftUI

/// Shared state driving the SwiftUI update window. The `Updater` sets a
/// pending prompt and awaits the user's choice; the window observes this
/// object and renders `UpdatePromptView` when a prompt is present.
@MainActor
final class UpdatePromptState: ObservableObject {
    static let windowID = "update-prompt"

    struct Prompt: Identifiable {
        let id = UUID()
        let kind: UpdatePromptView.Kind
        let notes: String
    }

    @Published private(set) var prompt: Prompt?

    private var continuation: CheckedContinuation<UpdatePromptView.Action, Never>?

    /// Presents a prompt and suspends until the user acts on it. The caller is
    /// responsible for opening the window (via `openWindow`) — see `Updater`.
    func present(kind: UpdatePromptView.Kind, notes: String) async -> UpdatePromptView.Action {
        // If a prompt is somehow already showing, resolve it as dismissed first.
        resolve(.dismiss)
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.prompt = Prompt(kind: kind, notes: notes)
        }
    }

    /// Delivers the user's choice (or window close) back to the awaiting caller.
    func resolve(_ action: UpdatePromptView.Action) {
        guard let continuation else { return }
        self.continuation = nil
        self.prompt = nil
        continuation.resume(returning: action)
    }
}
