import SwiftUI
import AppKit
import Combine

@main
struct MyWindowManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("My Window Manager", systemImage: "rectangle.split.3x1") {
            MenuBarContent()
                .environmentObject(delegate.store)
                .environmentObject(delegate.ax)
                .environmentObject(delegate.app)
                .environmentObject(delegate.hotkeys)
        }
        .menuBarExtraStyle(.menu)

        // 설정 창은 SwiftUI가 직접 소유하는 Window scene으로 연다. 이렇게 해야
        // NavigationSplitView 사이드바 머티리얼이 타이틀바(신호등) 영역까지
        // 정상적으로 채워진다 — 수동 NSWindow + NSHostingController에 욱여넣으면
        // SwiftUI가 윈도우 통합을 못 잡아 머티리얼이 타이틀바 밑에서만 그려진다.
        Window("My Window Manager", id: AppState.editorWindowID) {
            EditorRootView()
                .environmentObject(delegate.store)
                .environmentObject(delegate.catalog)
                .environmentObject(delegate.hotkeys)
                .environmentObject(delegate.app)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 980, height: 680)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let store = ConfigStore()
    let catalog = AppCatalog()
    let ax = AccessibilityManager.shared
    let hotkeys = HotkeyRegistryHolder()
    let app = AppState()

    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        app.store = store
        app.catalog = catalog
        app.ax = ax
        app.hotkeys = hotkeys
        hotkeys.registry.bind(store: store)

        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async { self?.hotkeys.registry.rebuild() }
            }
            .store(in: &cancellables)

        if !ax.isTrusted || store.needsSetup {
            app.openOnboarding()
            if !ax.isTrusted { ax.requestPermission() }
        }

        // Check for updates shortly after launch, then every 24h while
        // running (silent: alert only when an update is available).
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            Updater.startAutomaticChecks()
        }
    }
}
