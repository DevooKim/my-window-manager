import SwiftUI

enum EditorTab: String, CaseIterable, Identifiable {
    case presets, cycles, layouts, displays, move, general, info
    var id: String { rawValue }

    var label: String {
        switch self {
        case .presets: return "Resize Presets"
        case .cycles: return "Cycles"
        case .layouts: return "Layouts"
        case .displays: return "Displays"
        case .move: return "이동"
        case .general: return "일반"
        case .info: return "정보"
        }
    }

    /// SF Symbol name shown next to the label in the sidebar.
    var symbol: String {
        switch self {
        case .presets: return "rectangle.split.2x1"
        case .cycles: return "arrow.triangle.2.circlepath"
        case .layouts: return "rectangle.3.group"
        case .displays: return "display"
        case .move: return "arrow.left.arrow.right"
        case .general: return "gearshape"
        case .info: return "info.circle"
        }
    }

    /// Accent color applied to the sidebar icon.
    var tint: Color {
        switch self {
        case .presets: return .blue
        case .cycles: return .purple
        case .layouts: return .indigo
        case .displays: return .teal
        case .move: return .orange
        case .general: return .gray
        case .info: return .green
        }
    }

    /// 디테일 영역을 사이드바처럼 반투명(behind-window vibrancy)으로 그릴지.
    /// 캔버스가 있는 프리셋·사이클·레이아웃은 가독성을 위해 불투명 유지.
    var hasTranslucentDetail: Bool {
        switch self {
        case .info: return true
        case .presets, .cycles, .layouts, .displays, .move, .general: return false
        }
    }
}

struct EditorRootView: View {
    @EnvironmentObject var app: AppState

    private var selection: Binding<EditorTab> {
        Binding(get: { app.selectedTab }, set: { app.selectedTab = $0 })
    }

    var body: some View {
        NavigationSplitView {
            List(EditorTab.allCases, selection: selection) { tab in
                Label {
                    Text(tab.label)
                } icon: {
                    Image(systemName: tab.symbol)
                        .foregroundStyle(tab.tint)
                }
                .tag(tab)
            }
            // List 기본 배경을 끄고 그 뒤에 behind-window vibrancy를 깔아
            // 바탕화면이 비치게 한다.
            .scrollContentBackground(.hidden)
            .background(
                VisualEffectView(
                    material: .hudWindow,
                    state: .followsWindowActiveState,
                    makesHostWindowTransparent: true
                )
                .ignoresSafeArea()
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("")
                // 창이 투명하므로 디테일 영역은 배경 머티리얼을 깐다. 투명 탭
                // (정보)은 바탕이 잘 비치는 .hudWindow, 나머지는 불투명한
                // .windowBackground으로 가독성 유지.
                .background(
                    VisualEffectView(
                        material: app.selectedTab.hasTranslucentDetail ? .hudWindow : .windowBackground,
                        // 창이 포커스를 잃으면 불투명해진다.
                        state: .followsWindowActiveState,
                        // 위에 얹힌 텍스트가 vibrancy로 흐려지지 않게.
                        disablesVibrancy: true
                    )
                    .ignoresSafeArea()
                )
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch app.selectedTab {
        case .presets: PresetEditorView()
        case .cycles: CycleEditorView()
        case .layouts: LayoutEditorView()
        case .displays: DisplayDeadzoneView()
        case .move: MoveView()
        case .general: GeneralView()
        case .info: InfoView()
        }
    }
}
