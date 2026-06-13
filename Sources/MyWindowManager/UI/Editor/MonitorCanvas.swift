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
        let x = frame.x.resolve(in: monitorPixelSize.width) * sx
        let y = frame.y.resolve(in: monitorPixelSize.height) * sy
        let w = frame.width.resolve(in: monitorPixelSize.width) * sx
        let h = frame.height.resolve(in: monitorPixelSize.height) * sy
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func toMonitor(_ pt: CGPoint, canvas: CGSize) -> CGPoint {
        let sx = monitorPixelSize.width / max(1, canvas.width)
        let sy = monitorPixelSize.height / max(1, canvas.height)
        return CGPoint(x: pt.x * sx, y: pt.y * sy)
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
                let monStart = toMonitor(start, canvas: canvas)
                let monCur = toMonitor(cur, canvas: canvas)
                var x = min(monStart.x, monCur.x)
                var y = min(monStart.y, monCur.y)
                var w = abs(monCur.x - monStart.x)
                var h = abs(monCur.y - monStart.y)
                if snap {
                    x = snapValue(x, total: monitorPixelSize.width)
                    y = snapValue(y, total: monitorPixelSize.height)
                    w = snapValue(w, total: monitorPixelSize.width)
                    h = snapValue(h, total: monitorPixelSize.height)
                }
                area.x = inheritUnit(area.x, pixels: x, total: monitorPixelSize.width)
                area.y = inheritUnit(area.y, pixels: y, total: monitorPixelSize.height)
                area.width = inheritUnit(area.width, pixels: w, total: monitorPixelSize.width)
                area.height = inheritUnit(area.height, pixels: h, total: monitorPixelSize.height)
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
                let startX = start.x.resolve(in: monitorPixelSize.width)
                let startY = start.y.resolve(in: monitorPixelSize.height)
                let w = start.width.resolve(in: monitorPixelSize.width)
                let h = start.height.resolve(in: monitorPixelSize.height)
                var newX = clamp(startX + dxMon, 0, monitorPixelSize.width - w)
                var newY = clamp(startY + dyMon, 0, monitorPixelSize.height - h)
                if snap {
                    newX = snapValue(newX, total: monitorPixelSize.width)
                    newY = snapValue(newY, total: monitorPixelSize.height)
                }
                area.x = inheritUnit(start.x, pixels: newX, total: monitorPixelSize.width)
                area.y = inheritUnit(start.y, pixels: newY, total: monitorPixelSize.height)
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
                let sx = start.x.resolve(in: monitorPixelSize.width)
                let sy = start.y.resolve(in: monitorPixelSize.height)
                let sw = start.width.resolve(in: monitorPixelSize.width)
                let sh = start.height.resolve(in: monitorPixelSize.height)

                var newX = sx, newY = sy, newW = sw, newH = sh
                switch corner {
                case .topLeft:
                    newX = clamp(sx + dxMon, 0, sx + sw - 20)
                    newY = clamp(sy + dyMon, 0, sy + sh - 20)
                    newW = sw - (newX - sx)
                    newH = sh - (newY - sy)
                case .topRight:
                    newY = clamp(sy + dyMon, 0, sy + sh - 20)
                    newW = clamp(sw + dxMon, 20, monitorPixelSize.width - sx)
                    newH = sh - (newY - sy)
                case .bottomLeft:
                    newX = clamp(sx + dxMon, 0, sx + sw - 20)
                    newW = sw - (newX - sx)
                    newH = clamp(sh + dyMon, 20, monitorPixelSize.height - sy)
                case .bottomRight:
                    newW = clamp(sw + dxMon, 20, monitorPixelSize.width - sx)
                    newH = clamp(sh + dyMon, 20, monitorPixelSize.height - sy)
                }
                if snap {
                    newX = snapValue(newX, total: monitorPixelSize.width)
                    newY = snapValue(newY, total: monitorPixelSize.height)
                    newW = snapValue(newW, total: monitorPixelSize.width)
                    newH = snapValue(newH, total: monitorPixelSize.height)
                }
                area.x = inheritUnit(start.x, pixels: newX, total: monitorPixelSize.width)
                area.y = inheritUnit(start.y, pixels: newY, total: monitorPixelSize.height)
                area.width = inheritUnit(start.width, pixels: newW, total: monitorPixelSize.width)
                area.height = inheritUnit(start.height, pixels: newH, total: monitorPixelSize.height)
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
