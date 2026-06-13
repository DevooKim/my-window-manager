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
    @Binding var selection: EditorTab

    var body: some View {
        NavigationSplitView {
            List(EditorTab.allCases, selection: $selection) { tab in
                Label {
                    Text(tab.label)
                } icon: {
                    Image(systemName: tab.symbol)
                        .foregroundStyle(tab.tint)
                }
                .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .presets: PresetEditorView()
        case .cycles: CycleEditorView()
        case .layouts: LayoutEditorView()
        case .displays: DisplayDeadzoneView()
        case .general: GeneralView()
        case .info: InfoView()
        }
    }
}
