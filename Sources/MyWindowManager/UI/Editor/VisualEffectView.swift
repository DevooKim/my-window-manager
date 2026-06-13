import SwiftUI
import AppKit

/// Wraps an `NSVisualEffectView` so SwiftUI views can sit on a real
/// behind-window vibrancy material — the desktop/other windows show through,
/// unlike SwiftUI's `.background(.thinMaterial)` which only blurs in-window
/// content.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    /// behind-window vibrancy가 바탕화면을 비추려면 호스트 창이 불투명 배경을
    /// 그리지 않아야 한다. true면 이 뷰가 붙는 창을 투명 처리한다.
    var makesHostWindowTransparent: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        guard makesHostWindowTransparent else { return }
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }
}
