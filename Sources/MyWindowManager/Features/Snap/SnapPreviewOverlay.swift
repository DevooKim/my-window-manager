import AppKit

/// 드래그 중 스냅될 영역을 반투명 패널로 미리 보여준다.
/// 비활성(nonactivating)·클릭 통과라 드래그를 방해하지 않는다.
@MainActor
final class SnapPreviewOverlay {
    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.ignoresMouseEvents = true
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
        v.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        v.layer?.borderWidth = 2
        v.layer?.cornerRadius = 10
        p.contentView = v
        return p
    }()

    private var visible = false

    /// AX 좌표의 목표 프레임을 받아 표시한다. 이미 떠 있으면 부드럽게 이동.
    func show(axFrame: CGRect) {
        let target = ScreenHelper.cocoaRect(fromAX: axFrame)
        if visible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
            panel.orderFrontRegardless()
            visible = true
        }
    }

    func hide() {
        guard visible else { return }
        panel.orderOut(nil)
        visible = false
    }
}
