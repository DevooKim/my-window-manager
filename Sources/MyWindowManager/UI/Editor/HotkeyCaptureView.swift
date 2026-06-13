import SwiftUI
import AppKit

struct HotkeyCaptureView: View {
    @Binding var hotkey: HotkeyConfig?
    @EnvironmentObject var hotkeys: HotkeyRegistryHolder
    @State private var capturing = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(hotkey?.displayString ?? "(없음)")
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 80, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)))

            Button(capturing ? "키 누르세요..." : "변경") {
                startCapture()
            }
            .disabled(capturing)

            if hotkey != nil {
                Button("제거") { hotkey = nil }
            }
        }
        .onDisappear { stopCapture() }
    }

    private func startCapture() {
        capturing = true
        // Suspend global hotkeys so the combo we're about to press doesn't
        // also trigger an existing preset/cycle/layout.
        hotkeys.registry.setPaused(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // ESC
                stopCapture()
                return nil
            }
            if let cfg = HotkeyConfig.from(event: event) {
                hotkey = cfg
                stopCapture()
                return nil
            }
            return event
        }
    }

    private func stopCapture() {
        capturing = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        hotkeys.registry.setPaused(false)
    }
}

/// Inline warning shown next to a hotkey field when its combo collides with
/// another preset/cycle/layout. `selfId` is the item being edited (excluded
/// from the check). Renders nothing when there's no conflict.
struct HotkeyConflictWarning: View {
    @EnvironmentObject var store: ConfigStore
    let hotkey: HotkeyConfig?
    let selfId: UUID?

    var body: some View {
        let conflicts = hotkey.map { store.hotkeyConflicts(for: $0, excludingId: selfId) } ?? []
        if !conflicts.isEmpty {
            Label("\(conflicts.joined(separator: ", "))와(과) 겹침", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
