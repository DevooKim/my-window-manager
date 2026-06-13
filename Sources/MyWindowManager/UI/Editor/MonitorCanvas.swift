import SwiftUI

/// Fractions the editor snaps to, shared by the canvases and their grid overlay.
let snapSteps: [Double] = [0, 1.0/4, 1.0/3, 0.5, 2.0/3, 3.0/4, 1.0]

/// Dashed lines at the interior snap fractions, drawn over a monitor canvas
/// while the user is dragging so they can see what their region will snap to.
struct SnapGrid: View {
    let canvas: CGSize

    var body: some View {
        Canvas { ctx, _ in
            var path = Path()
            for step in snapSteps where step > 0 && step < 1 {
                let x = CGFloat(step) * canvas.width
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: canvas.height))
                let y = CGFloat(step) * canvas.height
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: canvas.width, y: y))
            }
            ctx.stroke(
                path,
                with: .color(Color.accentColor.opacity(0.5)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
        }
        .frame(width: canvas.width, height: canvas.height)
        .allowsHitTesting(false)
    }
}

enum Corner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}

/// Renders a monitor at its real aspect ratio and lets the user drag a
/// `RelativeFrame` region within it. Unit (ratio/px) per dimension is preserved.
struct MonitorCanvas: View {
    let monitorPixelSize: CGSize
    @Binding var area: RelativeFrame
    var snap: Bool = true
    /// Display this canvas represents, used to overlay its deadzone. Optional
    /// so callers that don't know the screen can omit it.
    var screen: NSScreen? = nil
    /// This display's deadzone, passed from the store so changes redraw and
    /// re-clamp immediately.
    var deadzone: DisplayDeadzone? = nil
    var onChange: (() -> Void)? = nil

    @State private var dragStart: RelativeFrame?
    @State private var dragStartPoint: CGPoint?
    @State private var isDragging = false

    private var aspect: CGFloat {
        guard monitorPixelSize.height > 0 else { return 16.0 / 10.0 }
        return monitorPixelSize.width / monitorPixelSize.height
    }

    var body: some View {
        GeometryReader { geo in
            let canvas = fitAspect(geo.size, aspect: aspect)
            let origin = CGPoint(
                x: (geo.size.width - canvas.width) / 2,
                y: (geo.size.height - canvas.height) / 2
            )
            let areaRect = canvasRect(of: area, canvas: canvas)

            ZStack(alignment: .topLeading) {
                // Empty space catcher — creates a new region by drag
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .underPageBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.6), lineWidth: 1.5)
                    )
                    .frame(width: canvas.width, height: canvas.height)
                    .offset(x: origin.x, y: origin.y)
                    .contentShape(Rectangle())
                    .gesture(newAreaGesture(canvas: canvas, origin: origin))

                // Snap grid — only while dragging with snap on
                if snap && isDragging {
                    SnapGrid(canvas: canvas)
                        .offset(x: origin.x, y: origin.y)
                }

                // Deadzone shading for this display (informational)
                DeadzoneOverlay(
                    monitorPixelSize: monitorPixelSize,
                    canvasSize: canvas,
                    screen: screen,
                    deadzone: deadzone
                )
                .offset(x: origin.x, y: origin.y)

                // Selected area
                Rectangle()
                    .fill(Color.accentColor.opacity(0.30))
                    .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 2))
                    .frame(width: max(0, areaRect.width), height: max(0, areaRect.height))
                    .offset(x: origin.x + areaRect.minX, y: origin.y + areaRect.minY)
                    .gesture(bodyGesture(canvas: canvas))

                // Corner handles
                ForEach(Corner.allCases, id: \.self) { corner in
                    cornerHandle(corner: corner, areaRect: areaRect,
                                 origin: origin, canvas: canvas)
                }
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
    }

    // MARK: - Geometry

    private func fitAspect(_ size: CGSize, aspect: CGFloat) -> CGSize {
        let w = min(size.width, size.height * aspect)
        let h = w / aspect
        return CGSize(width: max(0, w), height: max(0, h))
    }

    private func canvasRect(of frame: RelativeFrame, canvas: CGSize) -> CGRect {
        let sx = canvas.width / monitorPixelSize.width
        let sy = canvas.height / monitorPixelSize.height
        // Resolve the frame within the usable rect (deadzone applied), the same
        // area the appliers use — so the preview matches real placement and
        // sits inside the deadzone shading. `usableBounds` is the whole monitor
        // when there's no deadzone.
        let b = usableBounds
        let r = frame.resolve(in: b)
        return CGRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy)
    }

    private func toMonitor(_ pt: CGPoint, canvas: CGSize) -> CGPoint {
        let sx = monitorPixelSize.width / max(1, canvas.width)
        let sy = monitorPixelSize.height / max(1, canvas.height)
        return CGPoint(x: pt.x * sx, y: pt.y * sy)
    }

    /// Resolve one of the frame's edge units (x/y/width/height) into absolute
    /// monitor pixels, given that frame values are relative to the usable rect.
    /// Position units add the usable origin; size units don't.
    private func framePosX(_ u: FrameUnit) -> CGFloat { usableBounds.minX + u.resolve(in: usableBounds.width) }
    private func framePosY(_ u: FrameUnit) -> CGFloat { usableBounds.minY + u.resolve(in: usableBounds.height) }
    private func frameW(_ u: FrameUnit) -> CGFloat { u.resolve(in: usableBounds.width) }
    private func frameH(_ u: FrameUnit) -> CGFloat { u.resolve(in: usableBounds.height) }

    /// Inverse of `framePos*`/`frame[WH]`: turn an absolute-monitor-pixel value
    /// back into a FrameUnit relative to the usable rect, preserving its unit.
    private func unitPosX(_ original: FrameUnit, monitorPx: CGFloat) -> FrameUnit {
        inheritUnit(original, pixels: monitorPx - usableBounds.minX, total: usableBounds.width)
    }
    private func unitPosY(_ original: FrameUnit, monitorPx: CGFloat) -> FrameUnit {
        inheritUnit(original, pixels: monitorPx - usableBounds.minY, total: usableBounds.height)
    }
    private func unitW(_ original: FrameUnit, monitorPx: CGFloat) -> FrameUnit {
        inheritUnit(original, pixels: monitorPx, total: usableBounds.width)
    }
    private func unitH(_ original: FrameUnit, monitorPx: CGFloat) -> FrameUnit {
        inheritUnit(original, pixels: monitorPx, total: usableBounds.height)
    }

    /// The rect (in monitor pixels) regions are allowed to occupy. Equals the
    /// deadzone's usable rect when this screen has one, otherwise the whole
    /// monitor. Drag gestures clamp to these bounds.
    private var usableBounds: CGRect {
        DeadzoneGeometry.usableRectInMonitorPixels(for: screen, deadzone: deadzone)
            ?? CGRect(origin: .zero, size: monitorPixelSize)
    }

    // MARK: - Gestures

    private func newAreaGesture(canvas: CGSize, origin: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                isDragging = true
                let start = CGPoint(
                    x: clamp(value.startLocation.x - origin.x, 0, canvas.width),
                    y: clamp(value.startLocation.y - origin.y, 0, canvas.height)
                )
                let cur = CGPoint(
                    x: clamp(value.location.x - origin.x, 0, canvas.width),
                    y: clamp(value.location.y - origin.y, 0, canvas.height)
                )
                let b = usableBounds
                let monStart = toMonitor(start, canvas: canvas)
                let monCur = toMonitor(cur, canvas: canvas)
                // Clamp both drag corners into the usable rect first.
                let x0 = clamp(min(monStart.x, monCur.x), b.minX, b.maxX)
                let x1 = clamp(max(monStart.x, monCur.x), b.minX, b.maxX)
                let y0 = clamp(min(monStart.y, monCur.y), b.minY, b.maxY)
                let y1 = clamp(max(monStart.y, monCur.y), b.minY, b.maxY)
                var x = x0, y = y0, w = x1 - x0, h = y1 - y0
                if snap {
                    x = snapValue(x, total: monitorPixelSize.width)
                    y = snapValue(y, total: monitorPixelSize.height)
                    w = snapValue(w, total: monitorPixelSize.width)
                    h = snapValue(h, total: monitorPixelSize.height)
                    // Snapping is relative to the full monitor; pull back inside.
                    x = clamp(x, b.minX, b.maxX)
                    y = clamp(y, b.minY, b.maxY)
                    w = clamp(w, 0, b.maxX - x)
                    h = clamp(h, 0, b.maxY - y)
                }
                area.x = unitPosX(area.x, monitorPx: x)
                area.y = unitPosY(area.y, monitorPx: y)
                area.width = unitW(area.width, monitorPx: w)
                area.height = unitH(area.height, monitorPx: h)
                onChange?()
            }
            .onEnded { _ in dragStart = nil; isDragging = false }
    }

    private func bodyGesture(canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                isDragging = true
                if dragStart == nil { dragStart = area }
                guard let start = dragStart else { return }
                let dxCanvas = value.translation.width
                let dyCanvas = value.translation.height
                let dxMon = dxCanvas * monitorPixelSize.width / max(1, canvas.width)
                let dyMon = dyCanvas * monitorPixelSize.height / max(1, canvas.height)
                let startX = framePosX(start.x)
                let startY = framePosY(start.y)
                let w = frameW(start.width)
                let h = frameH(start.height)
                let b = usableBounds
                var newX = clamp(startX + dxMon, b.minX, max(b.minX, b.maxX - w))
                var newY = clamp(startY + dyMon, b.minY, max(b.minY, b.maxY - h))
                if snap {
                    newX = clamp(snapValue(newX, total: monitorPixelSize.width),
                                 b.minX, max(b.minX, b.maxX - w))
                    newY = clamp(snapValue(newY, total: monitorPixelSize.height),
                                 b.minY, max(b.minY, b.maxY - h))
                }
                area.x = unitPosX(start.x, monitorPx: newX)
                area.y = unitPosY(start.y, monitorPx: newY)
                onChange?()
            }
            .onEnded { _ in dragStart = nil; isDragging = false }
    }

    @ViewBuilder
    private func cornerHandle(corner: Corner, areaRect: CGRect,
                              origin: CGPoint, canvas: CGSize) -> some View {
        let size: CGFloat = 12
        let pos = corner.position(in: areaRect)
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .frame(width: size, height: size)
            .offset(x: origin.x + pos.x - size/2, y: origin.y + pos.y - size/2)
            .gesture(cornerGesture(corner: corner, canvas: canvas))
    }

    private func cornerGesture(corner: Corner, canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                isDragging = true
                if dragStart == nil { dragStart = area }
                guard let start = dragStart else { return }
                let dxMon = value.translation.width * monitorPixelSize.width / max(1, canvas.width)
                let dyMon = value.translation.height * monitorPixelSize.height / max(1, canvas.height)
                let sx = framePosX(start.x)
                let sy = framePosY(start.y)
                let sw = frameW(start.width)
                let sh = frameH(start.height)

                let b = usableBounds
                var newX = sx, newY = sy, newW = sw, newH = sh
                switch corner {
                case .topLeft:
                    newX = clamp(sx + dxMon, b.minX, sx + sw - 20)
                    newY = clamp(sy + dyMon, b.minY, sy + sh - 20)
                    newW = sw - (newX - sx)
                    newH = sh - (newY - sy)
                case .topRight:
                    newY = clamp(sy + dyMon, b.minY, sy + sh - 20)
                    newW = clamp(sw + dxMon, 20, b.maxX - sx)
                    newH = sh - (newY - sy)
                case .bottomLeft:
                    newX = clamp(sx + dxMon, b.minX, sx + sw - 20)
                    newW = sw - (newX - sx)
                    newH = clamp(sh + dyMon, 20, b.maxY - sy)
                case .bottomRight:
                    newW = clamp(sw + dxMon, 20, b.maxX - sx)
                    newH = clamp(sh + dyMon, 20, b.maxY - sy)
                }
                if snap {
                    newX = snapValue(newX, total: monitorPixelSize.width)
                    newY = snapValue(newY, total: monitorPixelSize.height)
                    newW = snapValue(newW, total: monitorPixelSize.width)
                    newH = snapValue(newH, total: monitorPixelSize.height)
                    // Keep the snapped edges inside the usable rect.
                    newX = clamp(newX, b.minX, b.maxX)
                    newY = clamp(newY, b.minY, b.maxY)
                    newW = clamp(newW, 20, b.maxX - newX)
                    newH = clamp(newH, 20, b.maxY - newY)
                }
                area.x = unitPosX(start.x, monitorPx: newX)
                area.y = unitPosY(start.y, monitorPx: newY)
                area.width = unitW(start.width, monitorPx: newW)
                area.height = unitH(start.height, monitorPx: newH)
                onChange?()
            }
            .onEnded { _ in dragStart = nil; isDragging = false }
    }

    // MARK: - Helpers

    private func inheritUnit(_ original: FrameUnit, pixels: CGFloat, total: CGFloat) -> FrameUnit {
        switch original {
        case .ratio:
            return .ratio(Double(pixels / max(1, total)))
        case .pixels:
            return .pixels(pixels)
        }
    }

    private func snapValue(_ v: CGFloat, total: CGFloat) -> CGFloat {
        let frac = v / max(1, total)
        let snapped = snapSteps.min(by: { abs($0 - Double(frac)) < abs($1 - Double(frac)) }) ?? Double(frac)
        if abs(snapped - Double(frac)) < 0.03 {
            return CGFloat(snapped) * total
        }
        return v
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(v, lo), hi)
    }
}
