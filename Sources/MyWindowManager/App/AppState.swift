import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    /// Scene id for the SwiftUI-owned settings window.
    static let editorWindowID = "editor"
    /// Scene id for the SwiftUI-owned About window (menu bar "정보").
    static let aboutWindowID = "about"
    /// UserDefaults key for whether the status-bar (menu bar) icon is shown.
    static let showMenuBarIconKey = "showMenuBarIcon"

    @Published var openedEditor: EditorTab? = nil
    @Published var selectedTab: EditorTab = .presets
    @Published var showOnboarding: Bool = false

    /// Injected from the SwiftUI scene so AppKit-side callers (menu bar,
    /// hotkeys) can open the editor window through SwiftUI's openWindow action.
    var openEditorWindow: (() -> Void)?
    /// Injected so the Updater can open the SwiftUI update window scene.
    var openUpdateWindow: (() -> Void)?
    /// Injected so the menu bar can open the SwiftUI About window scene.
    var openAboutWindow: (() -> Void)?

    private var onboardingWindow: NSWindow?

    weak var store: ConfigStore?
    weak var catalog: AppCatalog?
    weak var hotkeys: HotkeyRegistryHolder?
    weak var ax: AccessibilityManager?

    func openPresetEditor() { openEditor(.presets) }
    func openLayoutEditor() { openEditor(.layouts) }

    func openEditor(_ tab: EditorTab) {
        selectedTab = tab
        // 실제 윈도우 오픈은 SwiftUI scene이 담당한다. scene 쪽에서 주입한
        // openWindow 액션을 호출하고, 앱을 전면으로 가져온다.
        openEditorWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }

    func openOnboarding() {
        guard let ax, let store else { return }
        if let w = onboardingWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(
            rootView: AccessibilityPromptView(ax: ax, store: store, app: self)
        )
        let window = NSWindow(contentViewController: host)
        window.title = "권한"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = WindowCloseHandler.shared
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
    }
}

@MainActor
final class WindowCloseHandler: NSObject, NSWindowDelegate {
    static let shared = WindowCloseHandler()
    var onClose: ((NSWindow) -> Void)?
    func windowWillClose(_ notification: Notification) {
        if let w = notification.object as? NSWindow {
            onClose?(w)
        }
    }
}

@MainActor
final class HotkeyRegistryHolder: ObservableObject {
    let registry = HotkeyRegistry()
}
