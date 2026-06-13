import SwiftUI
import AppKit

/// Multi-placement canvas for the layout editor.
/// - Drag empty space  → create new placement
/// - Click placement   → select
/// - Drag body         → move
/// - Drag corner (when selected) → resize
struct LayoutMonitorCanvas: View {
    let monitorPixelSize: CGSize
    let displayIndex: Int
    @Binding var placements: [AppPlacement]
    @Binding var selection: UUID?

    let displayCount: Int
    var labelFor: (AppPlacement) -> String = { $0.bundleId }
    var onCreate: (RelativeFrame) -> AppPlacement
    /// Move a placement to another display by id and target display index.
    var onMoveToDisplay: (UUID, Int) -> Void = { _, _ in }
    /// Delete a placement by id.
    var onDelete: (UUID) -> Void = { _ in }
    var snap: Bool = true

    @State private var dragStart: RelativeFrame?
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

            ZStack(alignment: .topLeading) {
                // Monitor background — drag empty space to create
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .underPageBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.6), lineWidth: 1.5)
                    )
                    .frame(width: canvas.width, height: canvas.height)
                    .offset(x: origin.x, y: origin.y)
                    .contentShape(Rectangle())
                    .gesture(newPlacementGesture(canvas: canvas, origin: origin))

                // Snap grid — only while dragging with snap on
                if snap && isDragging {
                    SnapGrid(canvas: canvas)
                        .offset(x: origin.x, y: origin.y)
                }

                // Placements
                ForEach(placementIndices, id: \.self) { idx in
                    placementBox(idx: idx, canvas: canvas, origin: origin)
                }

                // Corner handles for the selected one
                if let selIdx = selectedIndex {
                    let rect = canvasRect(of: placements[selIdx].frame, canvas: canvas)
                    ForEach(Corner.allCases, id: \.self) { corner in
                        cornerHandle(corner: corner, rect: rect,
                                     origin: origin, canvas: canvas, idx: selIdx)
                    }
                }
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func placementBox(idx: Int, canvas: CGSize, origin: CGPoint) -> some View {
        let p = placements[idx]
        let rect = canvasRect(of: p.frame, canvas: canvas)
        let selected = selection == p.id

        Rectangle()
            .fill(Color.accentColor.opacity(selected ? 0.45 : 0.25))
            .overlay(
                Rectangle().stroke(
                    selected ? Color.accentColor : Color.accentColor.opacity(0.6),
                    lineWidth: selected ? 2 : 1
                )
            )
            .overlay(
                placementLabel(p, selected: selected, maxWidth: max(10, rect.width) - 6),
                alignment: .topLeading
            )
            .frame(width: max(10, rect.width), height: max(10, rect.height))
            .offset(x: origin.x + rect.minX, y: origin.y + rect.minY)
            .onTapGesture { selection = p.id }
            .gesture(bodyDragGesture(idx: idx, canvas: canvas))
            .contextMenu {
                if displayCount > 1 {
                    Menu("디스플레이로 이동") {
                        ForEach(0..<displayCount, id: \.self) { i in
                            Button("Display \(i + 1)") {
                                onMoveToDisplay(p.id, i)
                            }
                            .disabled(i == displayIndex)
                        }
                    }
                }
                Button("삭제", role: .destructive) {
                    onDelete(p.id)
                }
            }
    }

    @ViewBuilder
    private func placementLabel(_ p: AppPlacement, selected: Bool, maxWidth: CGFloat) -> some View {
        let bg: Color = selected ? Color.accentColor : Color.white.opacity(0.9)
        let fg: Color = selected ? .white : .black
        Text(labelFor(p))
            .font(.caption.weight(selected ? .bold : .medium))
            .foregroundStyle(fg)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .truncationMode(.middle)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(selected ? 0.9 : 0), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(selected ? 0.35 : 0.15),
                            radius: selected ? 2 : 1, y: 0.5)
            )
            .padding(3)
            .frame(maxWidth: maxWidth, alignment: .leading)
    }

    @ViewBuilder
    private func cornerHandle(corner: Corner, rect: CGRect,
                              origin: CGPoint, canvas: CGSize, idx: Int) -> some View {
        let size: CGFloat = 12
        let pos = corner.position(in: rect)
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .frame(width: size, height: size)
            .offset(x: origin.x + pos.x - size/2, y: origin.y + pos.y - size/2)
            .gesture(cornerGesture(corner: corner, idx: idx, canvas: canvas))
    }

    // MARK: - Gestures

    private func newPlacementGesture(canvas: CGSize, origin: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .local)
            .onChanged { value in
                isDragging = true
                let start = clampPoint(value.startLocation, origin: origin, canvas: canvas)
                let cur = clampPoint(value.location, origin: origin, canvas: canvas)
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
                let frame = RelativeFrame(
                    x: .ratio(Double(x / max(1, monitorPixelSize.width))),
                    y: .ratio(Double(y / max(1, monitorPixelSize.height))),
                    width: .ratio(Double(w / max(1, monitorPixelSize.width))),
                    height: .ratio(Double(h / max(1, monitorPixelSize.height)))
                )

                if let sel = selection,
                   let idx = placements.firstIndex(where: { $0.id == sel }),
                   dragStart != nil {
                    placements[idx].frame = frame
                } else {
                    if dragStart == nil {
                        let new = onCreate(frame)
                        placements.append(new)
                        selection = new.id
                        dragStart = frame
                    } else if let sel = selection,
                              let idx = placements.firstIndex(where: { $0.id == sel }) {
                        placements[idx].frame = frame
                    }
                }
            }
            .onEnded { _ in dragStart = nil; isDragging = false }
    }

    private func bodyDragGesture(idx: Int, canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                isDragging = true
                if dragStart == nil {
                    dragStart = placements[idx].frame
                    selection = placements[idx].id
                }
                guard let start = dragStart else { return }
                let dxMon = value.translation.width * monitorPixelSize.width / max(1, canvas.width)
                let dyMon = value.translation.height * monitorPixelSize.height / max(1, canvas.height)
                let sx = start.x.resolve(in: monitorPixelSize.width)
                let sy = start.y.resolve(in: monitorPixelSize.height)
                let w = start.width.resolve(in: monitorPixelSize.width)
                let h = start.height.resolve(in: monitorPixelSize.height)
                var newX = clamp(sx + dxMon, 0, monitorPixelSize.width - w)
                var newY = clamp(sy + dyMon, 0, monitorPixelSize.height - h)
                if snap {
                    newX = snapValue(newX, total: monitorPixelSize.width)
                    newY = snapValue(newY, total: monitorPixelSize.height)
                }
                placements[idx].frame.x = inheritUnit(start.x, pixels: newX, total: monitorPixelSize.width)
                placements[idx].frame.y = inheritUnit(start.y, pixels: newY, total: monitorPixelSize.height)
            }
            .onEnded { _ in dragStart = nil; isDragging = false }
    }

    private func cornerGesture(corner: Corner, idx: Int, canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                isDragging = true
                if dragStart == nil { dragStart = placements[idx].frame }
                guard let start = dragStart else { return }
                let dxMon = value.translation.width * monitorPixelSize.width / max(1, canvas.width)
                let dyMon = value.translation.height * monitorPixelSize.height / max(1, canvas.height)
                let sx = start.x.resolve(in: monitorPixelSize.width)
                let sy = start.y.resolve(in: monitorPixelSize.height)
                let sw = start.width.resolve(in: monitorPixelSize.width)
                let sh = start.height.resolve(in: monitorPixelSize.height)

                var nx = sx, ny = sy, nw = sw, nh = sh
                switch corner {
                case .topLeft:
                    nx = clamp(sx + dxMon, 0, sx + sw - 20)
                    ny = clamp(sy + dyMon, 0, sy + sh - 20)
                    nw = sw - (nx - sx)
                    nh = sh - (ny - sy)
                case .topRight:
                    ny = clamp(sy + dyMon, 0, sy + sh - 20)
                    nw = clamp(sw + dxMon, 20, monitorPixelSize.width - sx)
                    nh = sh - (ny - sy)
                case .bottomLeft:
                    nx = clamp(sx + dxMon, 0, sx + sw - 20)
                    nw = sw - (nx - sx)
                    nh = clamp(sh + dyMon, 20, monitorPixelSize.height - sy)
                case .bottomRight:
                    nw = clamp(sw + dxMon, 20, monitorPixelSize.width - sx)
                    nh = clamp(sh + dyMon, 20, monitorPixelSize.height - sy)
                }
                if snap {
                    nx = snapValue(nx, total: monitorPixelSize.width)
                    ny = snapValue(ny, total: monitorPixelSize.height)
                    nw = snapValue(nw, total: monitorPixelSize.width)
                    nh = snapValue(nh, total: monitorPixelSize.height)
                }
                placements[idx].frame.x = inheritUnit(start.x, pixels: nx, total: monitorPixelSize.width)
                placements[idx].frame.y = inheritUnit(start.y, pixels: ny, total: monitorPixelSize.height)
                placements[idx].frame.width = inheritUnit(start.width, pixels: nw, total: monitorPixelSize.width)
                placements[idx].frame.height = inheritUnit(start.height, pixels: nh, total: monitorPixelSize.height)
            }
            .onEnded { _ in dragStart = nil; isDragging = false }
    }

    // MARK: - Geometry helpers

    private func fitAspect(_ size: CGSize, aspect: CGFloat) -> CGSize {
        let w = min(size.width, size.height * aspect)
        let h = w / aspect
        return CGSize(width: max(0, w), height: max(0, h))
    }

    private func canvasRect(of frame: RelativeFrame, canvas: CGSize) -> CGRect {
        let sx = canvas.width / max(1, monitorPixelSize.width)
        let sy = canvas.height / max(1, monitorPixelSize.height)
        return CGRect(
            x: frame.x.resolve(in: monitorPixelSize.width) * sx,
            y: frame.y.resolve(in: monitorPixelSize.height) * sy,
            width: frame.width.resolve(in: monitorPixelSize.width) * sx,
            height: frame.height.resolve(in: monitorPixelSize.height) * sy
        )
    }

    private func toMonitor(_ pt: CGPoint, canvas: CGSize) -> CGPoint {
        let sx = monitorPixelSize.width / max(1, canvas.width)
        let sy = monitorPixelSize.height / max(1, canvas.height)
        return CGPoint(x: pt.x * sx, y: pt.y * sy)
    }

    private func clampPoint(_ pt: CGPoint, origin: CGPoint, canvas: CGSize) -> CGPoint {
        CGPoint(
            x: clamp(pt.x - origin.x, 0, canvas.width),
            y: clamp(pt.y - origin.y, 0, canvas.height)
        )
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(v, lo), hi)
    }

    private func inheritUnit(_ original: FrameUnit, pixels: CGFloat, total: CGFloat) -> FrameUnit {
        switch original {
        case .ratio: return .ratio(Double(pixels / max(1, total)))
        case .pixels: return .pixels(pixels)
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

    // MARK: - Filtering

    private var placementIndices: [Int] {
        placements.indices.filter { idx in
            match(placements[idx].displayMatcher, index: displayIndex)
        }
    }

    private var selectedIndex: Int? {
        guard let sel = selection else { return nil }
        guard let idx = placements.firstIndex(where: { $0.id == sel }) else { return nil }
        guard match(placements[idx].displayMatcher, index: displayIndex) else { return nil }
        return idx
    }

    private func match(_ matcher: DisplayMatcher, index: Int) -> Bool {
        switch matcher {
        case .primary: return index == 0
        case .index(let i): return i == index
        case .name(let n):
            return NSScreen.screens.indices.contains(index) &&
                NSScreen.screens[index].localizedName == n
        }
    }
}
