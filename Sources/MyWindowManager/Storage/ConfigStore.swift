import Foundation
import Carbon.HIToolbox
import Combine

struct AppConfig: Codable {
    var version: Int = 1
    var presets: [ResizePreset]
    var layouts: [Layout]
    var cycles: [PresetCycle]
    var deadzones: [DisplayDeadzone]

    init(presets: [ResizePreset], layouts: [Layout], cycles: [PresetCycle],
         deadzones: [DisplayDeadzone]) {
        self.presets = presets
        self.layouts = layouts
        self.cycles = cycles
        self.deadzones = deadzones
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        presets = try c.decodeIfPresent([ResizePreset].self, forKey: .presets) ?? []
        layouts = try c.decodeIfPresent([Layout].self, forKey: .layouts) ?? []
        // `cycles` was added later — older config.json files won't have it.
        cycles = try c.decodeIfPresent([PresetCycle].self, forKey: .cycles) ?? []
        // `deadzones` added later too.
        deadzones = try c.decodeIfPresent([DisplayDeadzone].self, forKey: .deadzones) ?? []
    }
}

@MainActor
final class ConfigStore: ObservableObject {
    @Published var presets: [ResizePreset] = []
    @Published var layouts: [Layout] = []
    @Published var cycles: [PresetCycle] = []
    @Published var deadzones: [DisplayDeadzone] = [] {
        didSet { syncDeadzones() }
    }

    /// Push the current deadzones into `ScreenHelper` so the appliers see them.
    private func syncDeadzones() {
        ScreenHelper.deadzonesByDisplayID = Dictionary(
            deadzones.map { ($0.displayID, $0) }, uniquingKeysWith: { a, _ in a }
        )
    }

    /// True when there is no config yet — the user hasn't picked a starter
    /// hotkey scheme. The onboarding flow shows the scheme picker in this case.
    @Published private(set) var needsSetup: Bool = false

    private let url: URL

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("MyWindowManager", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("config.json")
        load()
    }

    func load() {
        if let data = try? Data(contentsOf: url),
           let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) {
            self.presets = cfg.presets
            self.layouts = cfg.layouts
            self.cycles = cfg.cycles
            self.deadzones = cfg.deadzones
            self.needsSetup = false
        } else {
            // First launch — wait for the user to choose a starter scheme.
            self.presets = []
            self.layouts = []
            self.cycles = []
            self.deadzones = []
            self.needsSetup = true
        }
        syncDeadzones()
    }

    /// Seed the starter presets for the chosen scheme and persist. Also seeds a
    /// single "Halves" cycle over the four half presets (no hotkey). Layouts are
    /// left empty.
    func applyStarterScheme(_ scheme: PresetScheme) {
        let seeded = StarterPresets.presets(for: scheme)
        presets = seeded
        layouts = []

        // Cycle through the four halves, in id order, with no hotkey assigned.
        let halfNames = ["Left Half", "Right Half", "Top Half", "Bottom Half"]
        let halfIds = halfNames.compactMap { name in
            seeded.first { $0.name == name }?.id
        }
        cycles = halfIds.isEmpty ? [] : [
            PresetCycle(name: "Halves", presetIds: halfIds, hotkey: nil)
        ]

        needsSetup = false
        save()
    }

    func save() {
        let cfg = AppConfig(presets: presets, layouts: layouts, cycles: cycles, deadzones: deadzones)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(cfg) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Export / Import

    enum ConfigIOError: LocalizedError {
        case encodeFailed
        case readFailed
        case decodeFailed

        var errorDescription: String? {
            switch self {
            case .encodeFailed: return "설정을 인코딩하지 못했습니다."
            case .readFailed:   return "파일을 읽지 못했습니다."
            case .decodeFailed: return "올바른 설정 파일이 아닙니다."
            }
        }
    }

    /// Write the full configuration (presets, cycles, layouts) to a file.
    func export(to fileURL: URL) throws {
        let cfg = AppConfig(presets: presets, layouts: layouts, cycles: cycles, deadzones: deadzones)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(cfg) else { throw ConfigIOError.encodeFailed }
        try data.write(to: fileURL, options: .atomic)
    }

    /// Replace the current configuration with one loaded from a file, then
    /// persist it to the app's own config so it survives relaunch.
    func importConfig(from fileURL: URL) throws {
        guard let data = try? Data(contentsOf: fileURL) else { throw ConfigIOError.readFailed }
        guard let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            throw ConfigIOError.decodeFailed
        }
        presets = cfg.presets
        layouts = cfg.layouts
        cycles = cfg.cycles
        deadzones = cfg.deadzones
        needsSetup = false
        save()
    }

    func upsert(deadzone: DisplayDeadzone) {
        if let i = deadzones.firstIndex(where: { $0.displayID == deadzone.displayID }) {
            deadzones[i] = deadzone
        } else {
            deadzones.append(deadzone)
        }
        save()
    }

    func deleteDeadzone(displayID: String) {
        deadzones.removeAll { $0.displayID == displayID }
        save()
    }

    /// Clamp existing presets and layout placements into a display's new usable
    /// area after its deadzone changed. `usableSize` is the post-deadzone area
    /// of that display; `placementBelongsToDisplay` decides which layout
    /// placements target it. Presets are display-agnostic, so all are clamped
    /// against `usableSize` (ratio frames are unaffected — only fixed-pixel
    /// frames that overflow get trimmed). Returns the number of frames changed.
    ///
    /// Persists once at the end. Call from the deadzone "적용" flow, ideally
    /// after `upsert(deadzone:)` so the new geometry is already live.
    @discardableResult
    func migrateFrames(toUsableSize usableSize: CGSize,
                       placementBelongsToDisplay: (AppPlacement) -> Bool) -> Int {
        var changed = 0

        for i in presets.indices {
            if let clamped = presets[i].frame.clampedToUsable(usableSize) {
                presets[i].frame = clamped
                changed += 1
            }
        }

        for li in layouts.indices {
            for pi in layouts[li].placements.indices {
                guard placementBelongsToDisplay(layouts[li].placements[pi]) else { continue }
                if let clamped = layouts[li].placements[pi].frame.clampedToUsable(usableSize) {
                    layouts[li].placements[pi].frame = clamped
                    changed += 1
                }
            }
        }

        if changed > 0 { save() }
        return changed
    }

    func upsert(preset: ResizePreset) {
        if let i = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[i] = preset
        } else {
            presets.append(preset)
        }
        save()
    }

    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        save()
    }

    func upsert(layout: Layout) {
        if let i = layouts.firstIndex(where: { $0.id == layout.id }) {
            layouts[i] = layout
        } else {
            layouts.append(layout)
        }
        save()
    }

    func deleteLayout(id: UUID) {
        layouts.removeAll { $0.id == id }
        save()
    }

    func upsert(cycle: PresetCycle) {
        if let i = cycles.firstIndex(where: { $0.id == cycle.id }) {
            cycles[i] = cycle
        } else {
            cycles.append(cycle)
        }
        save()
    }

    func deleteCycle(id: UUID) {
        cycles.removeAll { $0.id == id }
        save()
    }

    func preset(by id: UUID) -> ResizePreset? {
        presets.first { $0.id == id }
    }

    // MARK: - Hotkey conflicts

    /// All bindings — across presets, cycles, and layouts — that use the same
    /// key combo as `config`, excluding the item identified by `excludingId`
    /// (the one being edited). Each entry is "<name> (<kind>)" for display.
    func hotkeyConflicts(for config: HotkeyConfig, excludingId: UUID?) -> [String] {
        func matches(_ other: HotkeyConfig?) -> Bool {
            guard let o = other else { return false }
            return o.keyCode == config.keyCode && o.modifiers == config.modifiers
        }
        var result: [String] = []
        for p in presets where p.id != excludingId && matches(p.hotkey) {
            result.append("\(p.name) (프리셋)")
        }
        for c in cycles where c.id != excludingId && matches(c.hotkey) {
            result.append("\(c.name) (사이클)")
        }
        for l in layouts where l.id != excludingId && matches(l.hotkey) {
            result.append("\(l.name) (레이아웃)")
        }
        return result
    }
}
