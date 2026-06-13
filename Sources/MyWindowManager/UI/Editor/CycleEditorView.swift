import SwiftUI

/// Editor for `PresetCycle`s — one hotkey bound to an ordered list of presets
/// that the same key steps through on each press.
struct CycleEditorView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var hotkeys: HotkeyRegistryHolder

    @State private var selection: UUID?
    @State private var draft: PresetCycle?

    var body: some View {
        HSplitView {
            sidebar
            detail
        }
        .onChange(of: selection) { _, newId in
            draft = store.cycles.first { $0.id == newId }
        }
        .onAppear {
            if selection == nil, let first = store.cycles.first {
                selection = first.id
                draft = first
            }
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        VStack(alignment: .leading) {
            List(selection: $selection) {
                ForEach(store.cycles) { cycle in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(cycle.name)
                            Text("\(cycle.presetIds.count) presets")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let h = cycle.hotkey {
                            Text(h.displayString)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(cycle.id as UUID?)
                }
            }
            HStack {
                Button(action: addCycle) { Image(systemName: "plus") }
                Button(action: deleteCycle) { Image(systemName: "minus") }
                    .disabled(selection == nil)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.bottom, 8)
        }
        .frame(minWidth: 220, idealWidth: 240)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if draft != nil {
            detailContent
        } else {
            Text("사이클을 선택하거나 추가하세요")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Name", text: nameBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Spacer()
                Text("Hotkey:")
                HotkeyCaptureView(hotkey: hotkeyBinding)
            }
            HotkeyConflictWarning(hotkey: draft?.hotkey, selfId: draft?.id)

            Text("같은 키를 반복해서 누르면 아래 순서대로 순환합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            presetList
            addPresetMenu

            HStack {
                Spacer()
                Button("저장") { saveDraft() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 480)
    }

    @ViewBuilder
    private var presetList: some View {
        List {
            ForEach(Array((draft?.presetIds ?? []).enumerated()), id: \.offset) { index, pid in
                HStack {
                    Text("\(index + 1).")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(store.preset(by: pid)?.name ?? "(삭제된 프리셋)")
                        .foregroundStyle(store.preset(by: pid) == nil ? .red : .primary)
                    Spacer()
                    Button {
                        removePreset(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .onMove { from, to in
                draft?.presetIds.move(fromOffsets: from, toOffset: to)
            }
        }
        .frame(minHeight: 200)
    }

    @ViewBuilder
    private var addPresetMenu: some View {
        Menu {
            ForEach(store.presets) { preset in
                Button(preset.name) { addPreset(preset.id) }
            }
        } label: {
            Label("프리셋 추가", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Bindings

    private var nameBinding: Binding<String> {
        Binding(get: { draft?.name ?? "" }, set: { draft?.name = $0 })
    }

    private var hotkeyBinding: Binding<HotkeyConfig?> {
        Binding(get: { draft?.hotkey }, set: { draft?.hotkey = $0 })
    }

    // MARK: - Actions

    private func addCycle() {
        let new = PresetCycle(name: "New Cycle")
        store.upsert(cycle: new)
        selection = new.id
        draft = new
        hotkeys.registry.rebuild()
    }

    private func deleteCycle() {
        guard let id = selection else { return }
        store.deleteCycle(id: id)
        selection = store.cycles.first?.id
        draft = store.cycles.first
        hotkeys.registry.rebuild()
    }

    private func addPreset(_ id: UUID) {
        draft?.presetIds.append(id)
    }

    private func removePreset(at index: Int) {
        guard var ids = draft?.presetIds, ids.indices.contains(index) else { return }
        ids.remove(at: index)
        draft?.presetIds = ids
    }

    private func saveDraft() {
        guard let d = draft else { return }
        store.upsert(cycle: d)
        hotkeys.registry.rebuild()
    }
}
