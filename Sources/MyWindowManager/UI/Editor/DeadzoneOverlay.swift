import SwiftUI
import AppKit

/// Visual overlay that shades a display's deadzone on an editor canvas. The
/// canvas draws the monitor's full pixel frame; the deadzone is defined as
/// insets off the *visible* frame, so we map both into canvas coordinates and
/// hatch the region windows can't be placed into.
///
/// The host canvas has already computed its fitted `canvasSize` (and centers it
/// via its own `origin`), so this view is sized to exactly `canvasSize` and the
/// host offsets it by the same `origin` as its other layers. Purely
/// informational — `allowsHitTesting(false)`.
struct DeadzoneOverlay: View {
    /// The monitor pixel size the host canvas uses as its coordinate space
    /// (typically `screen.frame.size`).
    let monitorPixelSize: CGSize
    /// The fitted canvas size the host drew the monitor at.
    let canvasSize: CGSize
    /// The screen this canvas represents, used for its visible-frame offset.
    /// `nil` (e.g. unresolved matcher) draws nothing.
    let screen: NSScreen?
    /// This display's deadzone (from the store, so changes redraw). `nil` or
    /// zero draws nothing.
    let deadzone: DisplayDeadzone?

    var body: some View {
        // Canvas == visible frame, so the deadzone draws directly with no
        // menu-bar offset. Only shown when there's a deadzone.
        if let usable = usableRect() {
            let useC = toCanvas(usable, canvas: canvasSize)

            ZStack(alignment: .topLeading) {
                // Darker shade over the deadzone (everything outside usable).
                Rectangle()
                    .fill(Color.black.opacity(0.30))
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .reverseMask {
                        Rectangle()
                            .frame(width: max(0, useC.width), height: max(0, useC.height))
                            .offset(x: useC.minX, y: useC.minY)
                    }
                // Orange dashed boundary of the usable (post-deadzone) area.
                Rectangle()
                    .stroke(
                        Color.orange.opacity(0.95),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
                    .frame(width: max(0, useC.width), height: max(0, useC.height))
                    .offset(x: useC.minX, y: useC.minY)
            }
            .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }

    private func usableRect() -> CGRect? {
        DeadzoneGeometry.usableRectInMonitorPixels(for: screen, deadzone: deadzone)
    }

    private func toCanvas(_ rect: CGRect, canvas: CGSize) -> CGRect {
        let sx = canvas.width / max(1, monitorPixelSize.width)
        let sy = canvas.height / max(1, monitorPixelSize.height)
        return CGRect(
            x: rect.minX * sx, y: rect.minY * sy,
            width: rect.width * sx, height: rect.height * sy
        )
    }
}

/// Shared geometry for deadzone-aware canvases: where the usable (post-deadzone)
/// rect lands in the monitor's full-pixel coordinate space — the space the
/// canvases draw and clamp their gestures in.
enum DeadzoneGeometry {
    /// The usable rect after applying a deadzone, in coordinates local to the
    /// visible frame (origin 0,0 = top-left of the visible area). The canvas is
    /// drawn in this same space (`monitorPixelSize == visibleFrame.size`), so no
    /// menu-bar offset is needed. `nil` when there's no deadzone.
    ///
    /// Pass the deadzone from an observed source (the store) so SwiftUI redraws
    /// on change — don't read the `ScreenHelper` static here.
    static func usableRectInMonitorPixels(for screen: NSScreen?,
                                          deadzone: DisplayDeadzone?) -> CGRect? {
        guard let screen, let dz = deadzone, !dz.isZero else { return nil }
        let visible = ScreenHelper.axVisibleFrame(of: screen)
        return dz.inset(CGRect(origin: .zero, size: visible.size))
    }

    /// Look up a screen's deadzone in a deadzone list by its stable ID.
    static func deadzone(for screen: NSScreen?, in deadzones: [DisplayDeadzone]) -> DisplayDeadzone? {
        guard let screen, let id = ScreenHelper.stableID(of: screen) else { return nil }
        return deadzones.first { $0.displayID == id }
    }
}

private extension View {
    /// Punches a hole in `self` shaped like `mask`, leaving the rest visible.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay(mask().blendMode(.destinationOut))
        }
    }
}
