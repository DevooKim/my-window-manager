import SwiftUI
import AppKit
import Combine

@main
struct MyWindowManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// 상태 막대(헤더 메뉴) 아이콘 표시 여부.
    @AppStorage(AppState.showMenuBarIconKey) private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarContent()
                .environmentObject(delegate.store)
                .environmentObject(delegate.ax)
                .environmentObject(delegate.app)
                .environmentObject(delegate.hotkeys)
        } label: {
            // label 클로저는 아이콘이 숨겨져도 SwiftUI가 평가하므로, 여기서
            // openWindow 액션을 주입해 메뉴 열림 여부와 무관하게 설정 창을 열 수
            // 있게 한다. (MenuBarContent.onAppear는 메뉴를 클릭해야만 불린다.)
            Image(systemName: "rectangle.split.3x1")
                .background(WindowOpenerInjector().environmentObject(delegate.app))
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

        // 업데이트 알림 창. Updater가 UpdatePromptState에 프롬프트를 설정한 뒤
        // openUpdateWindow 액션으로 이 창을 연다.
        Window("", id: UpdatePromptState.windowID) {
            UpdateWindowRoot()
                .environmentObject(delegate.updatePrompt)
                .environmentObject(delegate.app)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // 정보 창(메뉴바 "정보"). 표준 AppKit About 패널 대신 SwiftUI InfoView를
        // 띄워 GitHub 링크가 실제로 클릭되게 한다.
        Window("My Window Manager 정보", id: AppState.aboutWindowID) {
            InfoView()
                .frame(width: 320)
                .environmentObject(delegate.app)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let store = ConfigStore()
    let catalog = AppCatalog()
    let ax = AccessibilityManager.shared
    let hotkeys = HotkeyRegistryHolder()
    let app = AppState()
    let updatePrompt = UpdatePromptState()

    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        app.store = store
        app.catalog = catalog
        app.ax = ax
        app.hotkeys = hotkeys
        hotkeys.registry.bind(store: store)

        // 업데이트 창(SwiftUI scene)을 Updater와 연결한다.
        Updater.promptState = updatePrompt
        Updater.openWindow = { [weak app] in app?.openUpdateWindow?() }

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

    /// 이미 실행 중인 앱을 다시 열면(Finder/Dock/`open`) 설정 창을 띄운다.
    /// 헤더메뉴 아이콘을 숨겨 메뉴로 접근할 수 없을 때 복귀 경로가 된다.
    /// 아이콘이 꺼져 있으면 다시 켜서(= MenuBarContent가 openWindow 액션을
    /// 주입하도록) 설정 창을 열 수 있게 한다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 아이콘이 숨겨져 있으면 MenuBarExtra 안의 openWindow 인젝터가 평가되지
        // 않아 설정 창을 열 수 없다. 잠깐 아이콘을 켜서 인젝터가 주입되게 한 뒤
        // 설정 창을 연다. (아이콘은 사용자가 설정에서 다시 끌 수 있다.)
        if !UserDefaults.standard.bool(forKey: AppState.showMenuBarIconKey) {
            UserDefaults.standard.set(true, forKey: AppState.showMenuBarIconKey)
        }
        openEditorWhenReady(attempt: 0)
        return true
    }

    /// openWindow 액션은 MenuBarExtra 인젝터가 렌더된 뒤 주입되므로, 준비될
    /// 때까지 잠깐 재시도한 다음 설정 창을 연다. (최대 ~2초)
    private func openEditorWhenReady(attempt: Int) {
        if app.openEditorWindow != nil {
            app.openEditor(.general)
            return
        }
        guard attempt < 20 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.openEditorWhenReady(attempt: attempt + 1)
        }
    }
}
