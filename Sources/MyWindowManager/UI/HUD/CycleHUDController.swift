import SwiftUI
import AppKit

/// Shows a transient, click-through HUD panel while the user cycles through a
/// preset cycle. The panel never takes focus; it fades out ~1.2s after the
/// last `show` call (consecutive calls reset the timer, mirroring the macOS
/// volume HUD).
@MainActor
final class CycleHUDController {
    static let shared = CycleHUDController()

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?
    private let displayDuration: TimeInterval = 1.2

    private init() {}

    func show(cycleName: String, items: [HUDItem], currentIndex: Int, style: CycleHUDStyle) {
        guard style != .off, !items.isEmpty else { return }

        let root = CycleHUDView(
            cycleName: cycleName,
            items: items,
            currentIndex: currentIndex,
            style: style
        )

        let panel = panel ?? makePanel()
        self.panel = panel

        let host = NSHostingView(rootView: root)
        panel.contentView = host
        panel.layoutIfNeeded()

        // Size to fit the SwiftUI content, then center on the active screen.
        let fitting = host.fittingSize
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let origin = NSPoint(
            x: visible.midX - fitting.width / 2,
            y: visible.midY - fitting.height / 2
        )
        panel.setContentSize(fitting)
        panel.setFrameOrigin(origin)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }

        scheduleHide()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true        // click-through; never steals focus
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    private func scheduleHide() {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration, execute: work)
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }
}
