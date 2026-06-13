import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// "일반" tab — current-config summary and config backup (export / import).
/// Uses the grouped Form style shared with My AltTab's settings.
struct GeneralView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var hotkeys: HotkeyRegistryHolder

    var body: some View {
        Form {
            Section("현재 설정") {
                summaryRow("프리셋", store.presets.count)
                summaryRow("사이클", store.cycles.count)
                summaryRow("레이아웃", store.layouts.count)
            }
            Section {
                HStack {
                    Button {
                        exportConfig()
                    } label: {
                        Label("내보내기...", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        importConfig()
                    } label: {
                        Label("가져오기...", systemImage: "square.and.arrow.down")
                    }
                }
            } header: {
                Text("설정 백업")
            } footer: {
                Text("프리셋·사이클·레이아웃 전체를 JSON 파일로 저장하거나 불러옵니다. 가져오면 현재 설정을 덮어씁니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func summaryRow(_ label: String, _ count: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(count)개")
                .foregroundStyle(.secondary)
                .font(.system(.body, design: .monospaced))
        }
    }

    // MARK: - Export / Import

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MyWindowManager-config.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(to: url)
        } catch {
            presentError(error, title: "내보내기 실패")
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importConfig(from: url)
            hotkeys.registry.rebuild()
        } catch {
            presentError(error, title: "가져오기 실패")
        }
    }

    private func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
