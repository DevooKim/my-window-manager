import AppKit

@MainActor
final class RaycastCommandDispatcher {
    enum ResolvedCommand: Equatable {
        case preset(ResizePreset)
        case cycle(PresetCycle)
        case layout(Layout)
        case move(MoveAction)
        case size(SizeAction)
    }

    enum DispatchError: LocalizedError {
        case itemNotFound
        case noFocusedWindow

        var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "요청한 항목을 찾을 수 없습니다. Quicklink가 오래되었을 수 있습니다."
            case .noFocusedWindow:
                return "조작할 윈도우를 찾을 수 없습니다."
            }
        }
    }

    private let store: ConfigStore
    private let registry: HotkeyRegistry
    private let accessibility: AccessibilityManager
    private let onError: (String) -> Void
    private let onMissingAccessibility: () -> Void

    init(
        store: ConfigStore,
        registry: HotkeyRegistry,
        accessibility: AccessibilityManager,
        onError: @escaping (String) -> Void,
        onMissingAccessibility: @escaping () -> Void
    ) {
        self.store = store
        self.registry = registry
        self.accessibility = accessibility
        self.onError = onError
        self.onMissingAccessibility = onMissingAccessibility
    }

    static func resolve(
        _ command: RaycastCommand,
        presets: [ResizePreset],
        cycles: [PresetCycle],
        layouts: [Layout]
    ) throws -> ResolvedCommand {
        switch command {
        case .preset(let id):
            guard let preset = presets.first(where: { $0.id == id }) else {
                throw DispatchError.itemNotFound
            }
            return .preset(preset)
        case .cycle(let id):
            guard let cycle = cycles.first(where: { $0.id == id }) else {
                throw DispatchError.itemNotFound
            }
            return .cycle(cycle)
        case .layout(let id):
            guard let layout = layouts.first(where: { $0.id == id }) else {
                throw DispatchError.itemNotFound
            }
            return .layout(layout)
        case .move(let action):
            return .move(action)
        case .size(let action):
            return .size(action)
        }
    }

    func dispatch(_ command: RaycastCommand) {
        Task { await execute(command) }
    }

    private func execute(_ command: RaycastCommand) async {
        guard accessibility.isTrusted else {
            onMissingAccessibility()
            return
        }

        do {
            let resolved = try Self.resolve(
                command,
                presets: store.presets,
                cycles: store.cycles,
                layouts: store.layouts
            )

            if case .layout(let layout) = resolved {
                await LayoutApplier.apply(layout)
                return
            }

            guard await waitForEligibleFrontmostApplication() else {
                throw DispatchError.noFocusedWindow
            }

            let succeeded: Bool
            switch resolved {
            case .preset(let preset):
                succeeded = ResizeApplier.apply(preset)
            case .cycle(let cycle):
                let hasPreset = cycle.presetIds.contains { store.preset(by: $0) != nil }
                if hasPreset {
                    registry.advanceCycle(id: cycle.id)
                }
                succeeded = hasPreset
            case .move(let action):
                succeeded = action.isSpace
                    ? SpaceMover.move(direction: action.direction)
                    : DisplayMover.move(direction: action.direction)
            case .size(let action):
                succeeded = WindowSizer.step(action, ratio: store.sizeStepRatio)
            case .layout:
                succeeded = true
            }

            if !succeeded {
                throw DispatchError.noFocusedWindow
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            onError(message)
        }
    }

    private func waitForEligibleFrontmostApplication() async -> Bool {
        let excludedBundleIDs = [
            "com.raycast.macos",
            Bundle.main.bundleIdentifier,
        ].compactMap { $0 }

        for _ in 0..<20 {
            if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               !excludedBundleIDs.contains(bundleID) {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }
}
