import SwiftUI

enum EditorTab: String, CaseIterable, Identifiable {
    case presets, cycles, layouts, displays, general, info
    var id: String { rawValue }

    var label: String {
        switch self {
        case .presets: return "Resize Presets"
        case .cycles: return "Cycles"
        case .layouts: return "Layouts"
        case .displays: return "Displays"
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
        case .general: return .gray
        case .info: return .green
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
                VisualEffectView(material: .hudWindow, makesHostWindowTransparent: true)
                    .ignoresSafeArea()
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("")
                // 창을 투명 처리하므로 디테일 영역은 불투명 윈도우 머티리얼을
                // 깔아 가독성을 유지한다.
                .background(VisualEffectView(material: .windowBackground).ignoresSafeArea())
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch app.selectedTab {
        case .presets: PresetEditorView()
        case .cycles: CycleEditorView()
        case .layouts: LayoutEditorView()
        case .displays: DisplayDeadzoneView()
        case .general: GeneralView()
        case .info: InfoView()
        }
    }
}
