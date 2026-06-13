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
