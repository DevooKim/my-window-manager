import Foundation
import HotKey
import AppKit

@MainActor
final class HotkeyRegistry {
    enum Target {
        case preset(UUID)
        case layout(UUID)
        case cycle(UUID)
    }

    private var hotkeys: [(Target, HotKey)] = []
    private weak var store: ConfigStore?

    // Cycle progression state. Pressing the same cycle's hotkey consecutively
    // advances the index; pressing any other hotkey resets it (window-agnostic,
    // by design — see preset-cycle-design).
    private var lastCycleId: UUID?
    private var lastCycleIndex: Int = 0

    /// While paused, no global hotkeys are registered — used during hotkey
    /// capture so pressing an existing combo doesn't fire its preset/cycle.
    private var paused = false

    func bind(store: ConfigStore) {
        self.store = store
        rebuild()
    }

    /// Suspends or restores all global hotkeys. Capturing a new hotkey pauses
    /// the registry so the keypress isn't also consumed by an existing binding.
    func setPaused(_ value: Bool) {
        guard paused != value else { return }
        paused = value
        rebuild()
    }

    func rebuild() {
        hotkeys.removeAll()  // deinit unregisters each HotKey from the system

        // While paused, leave everything unregistered.
        guard !paused else { return }

        guard let store else { return }

        for preset in store.presets {
            guard let cfg = preset.hotkey, let hk = cfg.hotKey else { continue }
            let key = HotKey(key: hk.key, modifiers: hk.mods)
            let id = preset.id
            key.keyDownHandler = { [weak self, weak store] in
                guard let store, let p = store.presets.first(where: { $0.id == id }) else { return }
                self?.resetCycleState()
                _ = ResizeApplier.apply(p)
            }
            hotkeys.append((.preset(id), key))
        }

        for layout in store.layouts {
            guard let cfg = layout.hotkey, let hk = cfg.hotKey else { continue }
            let key = HotKey(key: hk.key, modifiers: hk.mods)
            let id = layout.id
            key.keyDownHandler = { [weak self, weak store] in
                guard let store, let l = store.layouts.first(where: { $0.id == id }) else { return }
                self?.resetCycleState()
                Task { await LayoutApplier.apply(l) }
            }
            hotkeys.append((.layout(id), key))
        }

        for cycle in store.cycles {
            guard let cfg = cycle.hotkey, let hk = cfg.hotKey else { continue }
            let key = HotKey(key: hk.key, modifiers: hk.mods)
            let id = cycle.id
            key.keyDownHandler = { [weak self] in
                self?.advanceCycle(id: id)
            }
            hotkeys.append((.cycle(id), key))
        }
    }

    /// Applies the next preset in a cycle. Same cycle pressed consecutively →
    /// advance and wrap; any other hotkey in between → start from index 0.
    /// Also called from the menu bar so menu clicks cycle the same way.
    func advanceCycle(id: UUID) {
        guard let store,
              let cycle = store.cycles.first(where: { $0.id == id }) else { return }
        let presets = cycle.presetIds.compactMap { store.preset(by: $0) }
        guard !presets.isEmpty else { return }

        let index: Int
        if lastCycleId == id {
            index = (lastCycleIndex + 1) % presets.count
        } else {
            index = 0
        }
        _ = ResizeApplier.apply(presets[index])
        lastCycleId = id
        lastCycleIndex = index
    }

    private func resetCycleState() {
        lastCycleId = nil
        lastCycleIndex = 0
    }
}
