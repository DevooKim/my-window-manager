import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var openedEditor: EditorTab? = nil
    @Published var showOnboarding: Bool = false

    private var editorWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    weak var store: ConfigStore?
    weak var catalog: AppCatalog?
    weak var hotkeys: HotkeyRegistryHolder?
    weak var ax: AccessibilityManager?

    func openPresetEditor() { openEditor(.presets) }
    func openLayoutEditor() { openEditor(.layouts) }

    func openEditor(_ tab: EditorTab) {
        guard let store, let catalog, let hotkeys else { return }
        if let w = editorWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = EditorRootView(initialTab: tab)
            .environmentObject(store)
            .environmentObject(catalog)
            .environmentObject(hotkeys)
        let host = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: host)
        window.title = "My Window Manager"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]

        // Open at the tab's preferred size, but never larger than the screen.
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size
            ?? NSSize(width: 1280, height: 800)
        let margin: CGFloat = 0.92
        let content = NSSize(
            width: min(tab.preferredSize.width, visible.width * margin),
            height: min(tab.preferredSize.height, visible.height * margin)
        )
        window.contentMinSize = NSSize(
            width: min(tab.minSize.width, content.width),
            height: min(tab.minSize.height, content.height)
        )
        window.setContentSize(content)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = WindowCloseHandler.shared
        WindowCloseHandler.shared.onClose = { [weak self] w in
            if w == self?.editorWindow { self?.editorWindow = nil }
            if w == self?.onboardingWindow { self?.onboardingWindow = nil }
        }
        editorWindow = window
        window.makeKeyAndOrderFront(nil)
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
