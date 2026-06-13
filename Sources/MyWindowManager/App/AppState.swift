import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var openedEditor: EditorTab? = nil
    @Published var selectedTab: EditorTab = .presets
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
        selectedTab = tab
        if let w = editorWindow {
            // 이미 열려 있으면 창을 리사이즈하지 않고 선택만 전환.
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = EditorRootView(selection: Binding(
            get: { [weak self] in self?.selectedTab ?? .presets },
            set: { [weak self] in self?.selectedTab = $0 }
        ))
        .environmentObject(store)
        .environmentObject(catalog)
        .environmentObject(hotkeys)
        let host = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: host)
        window.title = "My Window Manager"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.titlebarAppearsTransparent = true

        // 단일 기본 크기(가장 큰 레이아웃 기준), 화면보다 크지 않게 클램프.
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size
            ?? NSSize(width: 1280, height: 800)
        let margin: CGFloat = 0.92
        let defaultSize = NSSize(width: 980, height: 680)
        let minSize = NSSize(width: 720, height: 520)
        let content = NSSize(
            width: min(defaultSize.width, visible.width * margin),
            height: min(defaultSize.height, visible.height * margin)
        )
        window.contentMinSize = NSSize(
            width: min(minSize.width, content.width),
            height: min(minSize.height, content.height)
        )
        window.setContentSize(content)
        window.center()
        // 사용자가 조절한 크기를 재오픈/재실행 시 복원.
        window.setFrameAutosaveName("MyWindowManagerEditor")
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
