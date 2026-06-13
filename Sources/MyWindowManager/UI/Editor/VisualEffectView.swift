import SwiftUI
import AppKit

/// Wraps an `NSVisualEffectView` so SwiftUI views can sit on a real
/// behind-window vibrancy material — the desktop/other windows show through,
/// unlike SwiftUI's `.background(.thinMaterial)` which only blurs in-window
/// content.
/// `allowsVibrancy`를 끈 NSVisualEffectView. 기본값이 true면 머티리얼이 위에
/// 얹힌 텍스트를 배경에 맞춰 흐리게(vibrant) 렌더해 가독성이 떨어진다.
final class NonVibrantEffectView: NSVisualEffectView {
    override var allowsVibrancy: Bool { false }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    /// 창의 활성 상태를 따른다. `.followsWindowActiveState`면 창이 포커스를
    /// 잃었을 때 vibrancy가 꺼져 불투명해진다. `.active`는 항상 투명.
    var state: NSVisualEffectView.State = .active
    /// behind-window vibrancy가 바탕화면을 비추려면 호스트 창이 불투명 배경을
    /// 그리지 않아야 한다. true면 이 뷰가 붙는 창을 투명 처리한다.
    var makesHostWindowTransparent: Bool = false
    /// true면 위에 얹힌 텍스트가 vibrancy로 흐려지지 않게 한다.
    var disablesVibrancy: Bool = false
    /// 0보다 크면 호스트 창 contentView를 이 radius로 둥글게 클립한다. 투명 창은
    /// 시스템 윈도우 모서리 마스크가 적용되지 않아, 타이틀바 영역까지 포함해
    /// 직접 깎아야 모서리가 둥글게 보인다.
    var hostWindowCornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = disablesVibrancy ? NonVibrantEffectView() : NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        guard makesHostWindowTransparent || hostWindowCornerRadius > 0 else { return }
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            if makesHostWindowTransparent {
                window.isOpaque = false
                window.backgroundColor = .clear
            }
            if hostWindowCornerRadius > 0, let content = window.contentView {
                content.wantsLayer = true
                content.layer?.cornerRadius = hostWindowCornerRadius
                content.layer?.cornerCurve = .continuous
                content.layer?.masksToBounds = true
            }
        }
    }
}
