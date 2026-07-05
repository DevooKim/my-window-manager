import SwiftUI

/// "스냅" 탭 — 드래그 스냅의 항목별 on/off 설정.
struct SnapView: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        Form {
            Section {
                Toggle("드래그 스냅 사용", isOn: binding(\.enabled))
            } footer: {
                Text("창을 드래그해 화면 가장자리에 가져가면 자동으로 리사이즈됩니다. macOS 자체 창 타일링과 겹치면 미리보기가 이중으로 표시될 수 있으니, 시스템 설정 > 데스크탑 및 Dock > 창 타일링을 끄는 것을 권장합니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section("가장자리") {
                Toggle("왼쪽 — 왼쪽 절반", isOn: binding(\.edgeLeft))
                Toggle("오른쪽 — 오른쪽 절반", isOn: binding(\.edgeRight))
                Toggle("위 — 최대화", isOn: binding(\.edgeTop))
                Toggle("아래 — 아래 절반", isOn: binding(\.edgeBottom))
            }
            .disabled(!store.snapSettings.enabled)
            Section("부가 동작") {
                Toggle("모서리 쿼터 스냅", isOn: binding(\.corners))
                Toggle("미리보기 오버레이", isOn: binding(\.preview))
                Toggle("스냅 해제 시 크기 복원", isOn: binding(\.restoreOnUnsnap))
            }
            .disabled(!store.snapSettings.enabled)
        }
        .formStyle(.grouped)
    }

    private func binding(_ kp: WritableKeyPath<SnapSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.snapSettings[keyPath: kp] },
            set: { store.snapSettings[keyPath: kp] = $0 }
        )
    }
}
