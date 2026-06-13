import SwiftUI

struct AccessibilityPromptView: View {
    @ObservedObject var ax: AccessibilityManager
    @ObservedObject var store: ConfigStore
    var app: AppState? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: ax.isTrusted ? "checkmark.seal.fill" : "lock.shield")
                .font(.system(size: 44))
                .foregroundStyle(ax.isTrusted ? Color.green : Color.accentColor)

            Text(ax.isTrusted ? "권한이 부여되었습니다" : "Accessibility 권한이 필요합니다")
                .font(.title2.weight(.semibold))

            if ax.isTrusted {
                Text("이제 메뉴바 아이콘 또는 아래 버튼으로\n앱 메뉴를 사용할 수 있습니다.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text("My Window Manager가 윈도우를 이동/리사이즈하려면\n시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서\n앱을 허용해야 합니다.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if !ax.isTrusted {
                    Button("권한 요청") { ax.requestPermission() }
                        .keyboardShortcut(.defaultAction)
                    Button("설정 열기") { ax.openPreferences() }
                }
            }

            // Starter hotkey scheme — shown until the user picks one.
            if store.needsSetup {
                Divider().padding(.vertical, 4)
                schemePicker
            } else if ax.isTrusted, let app {
                Divider().padding(.vertical, 4)
                editorShortcuts(app)
            }
        }
        .padding(32)
        .frame(width: 480)
    }

    @ViewBuilder
    private var schemePicker: some View {
        VStack(spacing: 12) {
            Text("단축키 스타일을 선택하세요")
                .font(.headline)
            Text("자주 쓰는 윈도우 매니저와 비슷한 단축키로 시작합니다.\n나중에 프리셋 편집기에서 자유롭게 바꿀 수 있어요.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            ForEach(PresetScheme.allCases) { scheme in
                Button {
                    store.applyStarterScheme(scheme)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scheme.title).font(.body.weight(.medium))
                            Text(scheme.subtitle)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Button("나중에 직접 설정") {
                store.applyStarterScheme(.rectangle)
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }

    @ViewBuilder
    private func editorShortcuts(_ app: AppState) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    app.openPresetEditor()
                    app.closeOnboarding()
                } label: {
                    Label("프리셋 편집기", systemImage: "rectangle.split.2x1")
                }
                Button {
                    app.openLayoutEditor()
                    app.closeOnboarding()
                } label: {
                    Label("레이아웃 편집기", systemImage: "rectangle.3.group")
                }
            }
            Text("메뉴바 아이콘: 우측 상단 \u{25A6}")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
