import SwiftUI
import AppKit

/// "디스플레이" tab — per-display deadzones. Each connected display gets four
/// edge insets (상/하/좌/우, in pixels) that are carved off its usable area
/// before any preset or layout places a window there. Settings are stored by
/// the display's stable ID, so they follow the physical monitor.
///
/// Edits go to a local draft; "적용" commits them to the store (which redraws
/// the editor canvases and updates the appliers). "되돌리기" discards the draft.
struct DisplayDeadzoneView: View {
    @EnvironmentObject var store: ConfigStore

    /// Snapshot of currently connected displays, refreshed when the screen
    /// configuration changes.
    @State private var screens: [ScreenInfo] = DisplayDeadzoneView.currentScreens()

    /// In-progress edits, keyed by display ID. A display absent here mirrors the
    /// stored value (or zero if none stored).
    @State private var drafts: [String: DisplayDeadzone] = [:]

    /// Last migration result (display name, frames changed), shown as a banner
    /// after applying. Cleared when another edit starts.
    @State private var lastMigration: (name: String, count: Int)?

    struct ScreenInfo: Identifiable {
        let id: String        // stable display ID
        let name: String
        let size: CGSize      // visible (AX) area, for context
    }

    var body: some View {
        Form {
            if screens.isEmpty {
                Section {
                    Text("연결된 디스플레이를 찾을 수 없습니다.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(screens) { screen in
                    Section {
                        deadzoneEditor(for: screen)
                    } header: {
                        Text(screen.name)
                    } footer: {
                        Text("사용 영역 \(Int(screen.size.width))×\(Int(screen.size.height)) — 각 가장자리에서 비워둘 여백(px)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                if let m = lastMigration {
                    Section {
                        Label(
                            "\(m.name)의 프리셋·레이아웃 \(m.count)개를 새 영역에 맞게 조정했습니다.",
                            systemImage: "checkmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification)
        ) { _ in
            screens = Self.currentScreens()
        }
    }

    @ViewBuilder
    private func deadzoneEditor(for screen: ScreenInfo) -> some View {
        let dirty = isDirty(screen)
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                edgeField("상", edge(screen, \.top))
                edgeField("하", edge(screen, \.bottom))
            }
            HStack(spacing: 16) {
                edgeField("좌", edge(screen, \.left))
                edgeField("우", edge(screen, \.right))
            }
            HStack {
                Button("초기화") { resetToZero(screen) }
                    .controlSize(.small)
                    .disabled(current(screen).isZero)
                Spacer()
                Button("되돌리기") { drafts[screen.id] = nil }
                    .controlSize(.small)
                    .disabled(!dirty)
                Button("적용") { apply(screen) }
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!dirty)
            }
        }
    }

    private func edgeField(_ label: String, _ value: Binding<CGFloat>) -> some View {
        let doubleBinding = Binding(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = CGFloat($0) }
        )
        return HStack(spacing: 8) {
            Text(label)
                .frame(width: 20, alignment: .leading)
                .foregroundStyle(.secondary)
            TextField("", value: doubleBinding, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            Text("px").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Draft state

    /// The value currently shown — the draft if one exists, else the stored
    /// value, else a zero deadzone for this display.
    private func current(_ screen: ScreenInfo) -> DisplayDeadzone {
        if let d = drafts[screen.id] { return d }
        return stored(screen) ?? DisplayDeadzone(displayID: screen.id, displayName: screen.name)
    }

    private func stored(_ screen: ScreenInfo) -> DisplayDeadzone? {
        store.deadzones.first { $0.displayID == screen.id }
    }

    private func isDirty(_ screen: ScreenInfo) -> Bool {
        guard drafts[screen.id] != nil else { return false }
        let storedNonNil = stored(screen) ?? DisplayDeadzone(displayID: screen.id, displayName: screen.name)
        return current(screen) != storedNonNil
    }

    private func edge(_ screen: ScreenInfo,
                      _ keyPath: WritableKeyPath<DisplayDeadzone, CGFloat>) -> Binding<CGFloat> {
        Binding(
            get: { current(screen)[keyPath: keyPath] },
            set: { newVal in
                var dz = current(screen)
                dz[keyPath: keyPath] = max(0, newVal)
                drafts[screen.id] = dz
                lastMigration = nil
            }
        )
    }

    private func resetToZero(_ screen: ScreenInfo) {
        drafts[screen.id] = DisplayDeadzone(displayID: screen.id, displayName: screen.name)
    }

    private func apply(_ screen: ScreenInfo) {
        var dz = current(screen)
        dz.displayName = screen.name   // keep last-seen name fresh
        if dz.isZero {
            store.deleteDeadzone(displayID: screen.id)
        } else {
            store.upsert(deadzone: dz)
        }
        drafts[screen.id] = nil

        // Migrate existing frames into the new usable area for this display.
        // `screen.size` is the visible (pre-deadzone) area; insetting by the
        // (now-live) deadzone yields the usable size frames resolve against.
        let usableSize = dz.inset(CGRect(origin: .zero, size: screen.size)).size
        let changed = store.migrateFrames(toUsableSize: usableSize) { placement in
            placementBelongsTo(displayID: screen.id, matcher: placement.displayMatcher)
        }
        if changed > 0 { lastMigration = (screen.name, changed) }
    }

    /// True when a placement's display matcher resolves to the screen with this
    /// stable ID. Resolving through `ScreenHelper` keeps index/name/primary
    /// matchers in sync with the deadzone's ID-based identity.
    private func placementBelongsTo(displayID: String, matcher: DisplayMatcher) -> Bool {
        guard let screen = ScreenHelper.resolve(matcher) else { return false }
        return ScreenHelper.stableID(of: screen) == displayID
    }

    private static func currentScreens() -> [ScreenInfo] {
        NSScreen.screens.compactMap { screen in
            guard let id = ScreenHelper.stableID(of: screen) else { return nil }
            return ScreenInfo(
                id: id,
                name: screen.localizedName,
                size: ScreenHelper.axVisibleFrame(of: screen).size
            )
        }
    }
}
