import SwiftUI

/// A tiny monitor-shaped box that draws a `RelativeFrame` as a filled rect,
/// used in the cycle HUD's thumbnail style. Non-interactive.
struct PresetThumbnail: View {
    let frame: RelativeFrame
    /// The monitor area the frame is defined against, used to normalize px-based
    /// units to a 0–1 ratio so they draw correctly in the small box. Ratio-based
    /// units don't depend on this; px-based ones do.
    var monitorSize: CGSize = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1920, height: 1080)
    var size: CGSize = CGSize(width: 56, height: 35)
    var highlighted: Bool = false

    var body: some View {
        Canvas { ctx, canvasSize in
            // Resolve against the real monitor area, then scale into the box so
            // px and ratio units both map to the right fraction.
            let inMonitor = frame.resolve(in: CGRect(origin: .zero, size: monitorSize))
            let sx = monitorSize.width > 0 ? canvasSize.width / monitorSize.width : 0
            let sy = monitorSize.height > 0 ? canvasSize.height / monitorSize.height : 0
            let rect = CGRect(
                x: inMonitor.minX * sx,
                y: inMonitor.minY * sy,
                width: max(2, inMonitor.width * sx),
                height: max(2, inMonitor.height * sy)
            )
            let path = Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 2)
            ctx.fill(path, with: .color(highlighted ? .accentColor : .white.opacity(0.55)))
        }
        .background(
            RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08))
        )
        .frame(width: size.width, height: size.height)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(highlighted ? Color.accentColor : Color.white.opacity(0.15),
                              lineWidth: highlighted ? 2 : 1)
        )
    }
}
