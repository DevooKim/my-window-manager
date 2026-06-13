import SwiftUI
import AppKit

struct PresetEditorView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var hotkeys: HotkeyRegistryHolder
    @State private var selection: UUID?
    @State private var draft: ResizePreset?
    @State private var snap: Bool = true
    @State private var monitorIndex: Int = 0

    private var monitorPixelSize: CGSize {
        let screens = NSScreen.screens
        guard monitorIndex < screens.count else {
            return CGSize(width: 1920, height: 1080)
        }
        return screens[monitorIndex].frame.size
    }

    var body: some View {
        HSplitView {
            sidebar
            detail
        }
        .onChange(of: selection) { _, newId in
            draft = store.presets.first { $0.id == newId }
        }
        .onAppear {
            if selection == nil, let first = store.presets.first {
                selection = first.id
                draft = first
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(alignment: .leading) {
            List(selection: $selection) {
                ForEach(store.presets) { preset in
                    HStack {
                        Text(preset.name)
                        Spacer()
                        if let h = preset.hotkey {
                            Text(h.displayString)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(preset.id as UUID?)
                }
            }
            HStack {
                Button(action: addPreset) { Image(systemName: "plus") }
                Button(action: deletePreset) { Image(systemName: "minus") }
                    .disabled(selection == nil)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.bottom, 8)
        }
        .frame(minWidth: 220, idealWidth: 240)
    }

    @ViewBuilder
    private var detail: some View {
        if draft != nil {
            detailContent
        } else {
            Text("프리셋을 선택하거나 추가하세요")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            detailHeader
            MonitorCanvas(
                monitorPixelSize: monitorPixelSize,
                area: frameBinding,
                snap: snap
            )
            .frame(minHeight: 260)

            Toggle("Snap to common ratios (1/4, 1/3, 1/2 ...)", isOn: $snap)
            Divider()
            RelativeFrameInspector(frame: frameBinding, monitorSize: monitorPixelSize)

            HStack {
                Text("Hotkey:")
                HotkeyCaptureView(hotkey: hotkeyBinding)
            }
            HotkeyConflictWarning(hotkey: draft?.hotkey, selfId: draft?.id)

            HStack {
                Button("현재 윈도우에 적용 (미리보기)") {
                    if let d = draft { _ = ResizeApplier.apply(d) }
                }
                Spacer()
                Button("리셋") { resetDraft() }
                    .disabled(!hasUnsavedChanges)
                Button("저장") { saveDraft() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 480)
    }

    @ViewBuilder
    private var detailHeader: some View {
        HStack {
            TextField("Name", text: nameBinding)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
            Spacer()
            if NSScreen.screens.count > 1 {
                Picker("Preview on", selection: $monitorIndex) {
                    ForEach(0..<NSScreen.screens.count, id: \.self) { i in
                        Text("Display \(i+1)").tag(i)
                    }
                }
                .frame(width: 180)
            }
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { draft?.name ?? "" },
            set: { draft?.name = $0 }
        )
    }

    private var frameBinding: Binding<RelativeFrame> {
        Binding(
            get: { draft?.frame ?? .leftHalf },
            set: { draft?.frame = $0 }
        )
    }

    private var hotkeyBinding: Binding<HotkeyConfig?> {
        Binding(
            get: { draft?.hotkey },
            set: { draft?.hotkey = $0 }
        )
    }

    private func addPreset() {
        let new = ResizePreset(name: "New Preset", frame: .leftHalf)
        store.upsert(preset: new)
        selection = new.id
        draft = new
        hotkeys.registry.rebuild()
    }

    private func deletePreset() {
        guard let id = selection else { return }
        store.deletePreset(id: id)
        selection = store.presets.first?.id
        draft = store.presets.first
        hotkeys.registry.rebuild()
    }

    private func saveDraft() {
        guard let d = draft else { return }
        store.upsert(preset: d)
        hotkeys.registry.rebuild()
    }

    /// Whether the draft differs from the saved preset (a brand-new preset
    /// not yet in the store also counts as having unsaved changes).
    private var hasUnsavedChanges: Bool {
        guard let d = draft else { return false }
        guard let saved = store.preset(by: d.id) else { return true }
        return saved != d
    }

    /// Discard unsaved edits, restoring the draft to the last saved state.
    private func resetDraft() {
        guard let id = draft?.id, let saved = store.preset(by: id) else { return }
        draft = saved
    }
}
