import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// "정보" tab — app summary plus configuration export / import.
struct InfoView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var hotkeys: HotkeyRegistryHolder

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        switch (v, b) {
        case let (v?, b?): return "\(v) (\(b))"
        case let (v?, nil): return v
        default: return "—"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            GroupBox("현재 설정") {
                VStack(alignment: .leading, spacing: 6) {
                    summaryRow("프리셋", store.presets.count)
                    summaryRow("사이클", store.cycles.count)
                    summaryRow("레이아웃", store.layouts.count)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox("설정 백업") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("프리셋·사이클·레이아웃 전체를 JSON 파일로 저장하거나 불러옵니다. 가져오면 현재 설정을 덮어씁니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            Spacer()
        }
        .padding(20)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("My Window Manager")
                    .font(.title2.weight(.semibold))
                Text("버전 \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("업데이트 확인") { Updater.checkForUpdates(silent: false) }
        }
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
