import SwiftUI

enum EditorTab: String, CaseIterable, Identifiable {
    case presets, cycles, layouts, general, info
    var id: String { rawValue }
    var label: String {
        switch self {
        case .presets: return "Resize Presets"
        case .cycles: return "Cycles"
        case .layouts: return "Layouts"
        case .general: return "일반"
        case .info: return "정보"
        }
    }

    /// Preferred window size when this tab is opened. Layouts needs the most
    /// room for its multi-monitor canvases; presets/cycles are more compact.
    var preferredSize: NSSize {
        switch self {
        case .presets: return NSSize(width: 720, height: 560)
        case .cycles:  return NSSize(width: 760, height: 580)
        case .layouts: return NSSize(width: 980, height: 680)
        case .general: return NSSize(width: 620, height: 520)
        case .info:    return NSSize(width: 460, height: 420)
        }
    }

    /// Smallest usable size for this tab.
    var minSize: NSSize {
        switch self {
        case .presets: return NSSize(width: 620, height: 460)
        case .cycles:  return NSSize(width: 640, height: 480)
        case .layouts: return NSSize(width: 760, height: 520)
        case .general: return NSSize(width: 520, height: 440)
        case .info:    return NSSize(width: 420, height: 380)
        }
    }
}

struct EditorRootView: View {
    @State var initialTab: EditorTab = .presets

    var body: some View {
        TabView(selection: $initialTab) {
            PresetEditorView()
                .tabItem { Label("프리셋", systemImage: "rectangle.split.2x1") }
                .tag(EditorTab.presets)
            CycleEditorView()
                .tabItem { Label("사이클", systemImage: "arrow.triangle.2.circlepath") }
                .tag(EditorTab.cycles)
            LayoutEditorView()
                .tabItem { Label("레이아웃", systemImage: "rectangle.3.group") }
                .tag(EditorTab.layouts)
            GeneralView()
                .tabItem { Label("일반", systemImage: "gearshape") }
                .tag(EditorTab.general)
            InfoView()
                .tabItem { Label("정보", systemImage: "info.circle") }
                .tag(EditorTab.info)
        }
    }
}
