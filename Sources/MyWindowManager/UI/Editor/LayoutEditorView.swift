import SwiftUI
import AppKit

private enum LaunchTargetKind: String, Hashable {
    case none, path, url
}

struct LayoutEditorView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var catalog: AppCatalog
    @EnvironmentObject var hotkeys: HotkeyRegistryHolder

    @State private var selection: UUID?
    @State private var draft: Layout?
    @State private var selectedPlacement: UUID?
    @State private var snap: Bool = true

    var body: some View {
        HSplitView {
            // Sidebar
            VStack {
                List(selection: $selection) {
                    ForEach(store.layouts) { layout in
                        HStack {
                            Text(layout.name)
                            Spacer()
                            if let h = layout.hotkey {
                                Text(h.displayString)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(layout.id as UUID?)
                    }
                }
                HStack {
                    Button(action: addLayout) { Image(systemName: "plus") }
                    Button(action: deleteLayout) { Image(systemName: "minus") }
                        .disabled(selection == nil)
                    Spacer()
                }
                .padding(.horizontal, 8).padding(.bottom, 8)
            }
            .frame(minWidth: 220)

            // Detail
            if draft != nil {
                detailView
            } else {
                Text("레이아웃을 선택하거나 추가하세요")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: selection) { _, new in
            draft = store.layouts.first { $0.id == new }
            selectedPlacement = draft?.placements.first?.id
        }
    }

    @ViewBuilder
    private var detailView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Layout name", text: Binding(
                    get: { draft?.name ?? "" },
                    set: { draft?.name = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                Spacer()
                HotkeyCaptureView(hotkey: Binding(
                    get: { draft?.hotkey },
                    set: { draft?.hotkey = $0 }
                ))
            }
            HotkeyConflictWarning(hotkey: draft?.hotkey, selfId: draft?.id)

            // Multi-monitor canvas grid
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { idx, screen in
                        monitorPanel(index: idx, screen: screen)
                    }
                }
                .padding(.vertical, 8)
            }

            HStack {
                Button(action: addPlacement) {
                    Label("앱 추가", systemImage: "plus")
                }
                Text("또는 모니터 위를 드래그해서 영역을 그리세요")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Snap to common ratios (1/4, 1/3, 1/2 ...)", isOn: $snap)
            }

            Divider()

            if let pid = selectedPlacement,
               let pidx = draft?.placements.firstIndex(where: { $0.id == pid }),
               let d = draft {
                placementInspector(index: pidx, placement: d.placements[pidx])
            } else {
                Text("‘앱 추가’를 누르거나 모니터 위를 드래그해 영역을 만든 뒤, 클릭하면 상세 설정이 나타납니다")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("지금 적용") {
                    if let d = draft { Task { await LayoutApplier.apply(d) } }
                }
                Spacer()
                Button("저장") { saveDraft() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 560)
    }

    private func monitorPanel(index idx: Int, screen: NSScreen) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Display \(idx + 1) — \(screen.localizedName)")
                .font(.caption).foregroundStyle(.secondary)

            LayoutMonitorCanvas(
                monitorPixelSize: screen.visibleFrame.size,
                displayIndex: idx,
                placements: Binding(
                    get: { draft?.placements ?? [] },
                    set: { draft?.placements = $0 }
                ),
                selection: $selectedPlacement,
                screen: screen,
                deadzone: DeadzoneGeometry.deadzone(for: screen, in: store.deadzones),
                displayCount: NSScreen.screens.count,
                labelFor: { p in
                    let appName = catalog.find(p.bundleId)?.name ?? p.bundleId
                    switch p.target {
                    case .none: return appName
                    case .path(let s), .url(let s):
                        let trimmed = (s as NSString).lastPathComponent
                        return "\(appName) — \(trimmed.isEmpty ? s : trimmed)"
                    }
                },
                onCreate: { frame in
                    AppPlacement(
                        bundleId: catalog.apps.first?.bundleId ?? "",
                        displayMatcher: .index(idx),
                        frame: frame
                    )
                },
                onMoveToDisplay: { id, newIdx in
                    if let pidx = draft?.placements.firstIndex(where: { $0.id == id }) {
                        moveToDisplay(placementIndex: pidx, newDisplayIndex: newIdx)
                        selectedPlacement = id
                    }
                },
                onDelete: { id in deletePlacement(id: id) },
                snap: snap
            )
            .frame(width: 360, height: 360 * screen.frame.height / max(1, screen.frame.width))
        }
    }

    @ViewBuilder
    private func placementInspector(index: Int, placement: AppPlacement) -> some View {
        let screen = ScreenHelper.resolve(placement.displayMatcher) ?? NSScreen.main!
        let monSize = screen.frame.size
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("App:")
                AppPickerView(selectedBundleId: Binding(
                    get: { draft?.placements[index].bundleId ?? "" },
                    set: { draft?.placements[index].bundleId = $0 }
                ))
                Toggle("Launch if needed", isOn: Binding(
                    get: { draft?.placements[index].launchIfNeeded ?? false },
                    set: { draft?.placements[index].launchIfNeeded = $0 }
                ))
                Spacer()
                Button("삭제") { deletePlacement(id: placement.id) }
            }

            RelativeFrameInspector(frame: Binding(
                get: { draft?.placements[index].frame ?? .leftHalf },
                set: { draft?.placements[index].frame = $0 }
            ), monitorSize: monSize)

            HStack {
                Text("Display:")
                Picker("", selection: Binding(
                    get: { displayMatcherIndex(draft?.placements[index].displayMatcher ?? .primary) },
                    set: { newIdx in
                        moveToDisplay(placementIndex: index, newDisplayIndex: newIdx)
                    }
                )) {
                    ForEach(0..<NSScreen.screens.count, id: \.self) { i in
                        Text("Display \(i+1)").tag(i)
                    }
                }
                .frame(width: 160)
                Text("(비율 유지)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            launchTargetEditor(index: index)
        }
    }

    @ViewBuilder
    private func launchTargetEditor(index: Int) -> some View {
        let target = draft?.placements[index].target ?? .none
        let kind: LaunchTargetKind = {
            switch target {
            case .none: return .none
            case .path: return .path
            case .url: return .url
            }
        }()

        HStack(alignment: .center) {
            Text("Open:")
            Picker("", selection: Binding(
                get: { kind },
                set: { newKind in
                    let currentValue = target.displayString
                    switch newKind {
                    case .none: draft?.placements[index].target = .none
                    case .path: draft?.placements[index].target = .path(currentValue)
                    case .url:  draft?.placements[index].target = .url(currentValue)
                    }
                }
            )) {
                Text("앱만 실행").tag(LaunchTargetKind.none)
                Text("경로/파일").tag(LaunchTargetKind.path)
                Text("URL").tag(LaunchTargetKind.url)
            }
            .frame(width: 200)

            switch kind {
            case .none:
                Text("기존 윈도우를 재사용합니다")
                    .font(.caption2).foregroundStyle(.secondary)
            case .path:
                TextField("~/Dev/myproject", text: pathBinding(index: index))
                    .textFieldStyle(.roundedBorder)
                Button("선택...") { choosePath(placementIndex: index) }
            case .url:
                TextField("https://example.com", text: urlBinding(index: index))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func pathBinding(index: Int) -> Binding<String> {
        Binding(
            get: {
                if case .path(let p) = draft?.placements[index].target { return p }
                return ""
            },
            set: { draft?.placements[index].target = .path($0) }
        )
    }

    private func urlBinding(index: Int) -> Binding<String> {
        Binding(
            get: {
                if case .url(let u) = draft?.placements[index].target { return u }
                return ""
            },
            set: { draft?.placements[index].target = .url($0) }
        )
    }

    private func choosePath(placementIndex idx: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            draft?.placements[idx].target = .path(url.path)
        }
    }

    /// Move a placement to a different display, preserving its *relative* size.
    /// Ratio units are kept verbatim, so "left half" stays "left half" of
    /// whatever monitor it lands on. Pixel units are clamped to fit the new
    /// monitor (a fixed-px box never ends up larger than the screen).
    private func moveToDisplay(placementIndex idx: Int, newDisplayIndex newIdx: Int) {
        guard var p = draft?.placements[idx] else { return }
        let screens = NSScreen.screens
        guard newIdx < screens.count else {
            p.displayMatcher = .index(newIdx)
            draft?.placements[idx] = p
            return
        }
        let newSize = screens[newIdx].frame.size

        // Ratio units carry over unchanged. Only clamp absolute-pixel units so
        // a fixed-size box can't exceed the new (possibly smaller) monitor.
        p.frame.width = clampPxUnit(p.frame.width, max: newSize.width)
        p.frame.height = clampPxUnit(p.frame.height, max: newSize.height)
        let w = p.frame.width.resolve(in: newSize.width)
        let h = p.frame.height.resolve(in: newSize.height)
        p.frame.x = clampPxUnit(p.frame.x, max: newSize.width - w)
        p.frame.y = clampPxUnit(p.frame.y, max: newSize.height - h)

        p.displayMatcher = .index(newIdx)
        draft?.placements[idx] = p
    }

    /// Clamp a pixel-typed unit to `[0, max]`; ratio units pass through.
    private func clampPxUnit(_ unit: FrameUnit, max upper: CGFloat) -> FrameUnit {
        switch unit {
        case .ratio: return unit
        case .pixels(let px): return .pixels(min(Swift.max(0, px), Swift.max(0, upper)))
        }
    }

    private func displayMatcherIndex(_ m: DisplayMatcher) -> Int {
        switch m {
        case .primary: return 0
        case .index(let i): return i
        case .name(let n): return NSScreen.screens.firstIndex { $0.localizedName == n } ?? 0
        }
    }

    private func addLayout() {
        let new = Layout(name: "New Layout", placements: [])
        store.upsert(layout: new)
        selection = new.id
        draft = new
        hotkeys.registry.rebuild()
    }

    private func deleteLayout() {
        guard let id = selection else { return }
        store.deleteLayout(id: id)
        selection = store.layouts.first?.id
        draft = store.layouts.first
        hotkeys.registry.rebuild()
    }

    /// Adds a new placement to the current layout on the primary display with a
    /// default left-half frame, and selects it so the inspector opens right away.
    private func addPlacement() {
        guard draft != nil else { return }
        let new = AppPlacement(
            bundleId: catalog.apps.first?.bundleId ?? "",
            displayMatcher: .index(0),
            frame: .leftHalf
        )
        draft?.placements.append(new)
        selectedPlacement = new.id
    }

    private func deletePlacement(id: UUID) {
        draft?.placements.removeAll { $0.id == id }
        selectedPlacement = draft?.placements.first?.id
    }

    private func saveDraft() {
        guard let d = draft else { return }
        store.upsert(layout: d)
        hotkeys.registry.rebuild()
    }
}
