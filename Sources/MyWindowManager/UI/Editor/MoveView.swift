import SwiftUI

/// "이동" 탭 — 포커스 창을 인접 디스플레이/스페이스로 옮기는 액션의 핫키 설정.
struct MoveView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var hotkeys: HotkeyRegistryHolder

    var body: some View {
        Form {
            Section("디스플레이") {
                row(.displayPrev)
                row(.displayNext)
            }
            Section {
                row(.spacePrev)
                row(.spaceNext)
            } header: {
                Text("스페이스")
            } footer: {
                Text("스페이스 이동은 비공개 기능을 사용하며, 화면 전환은 시스템 설정 > 키보드 > Mission Control 의 \"한 스페이스 왼쪽/오른쪽으로 이동\" 단축키(⌃←/⌃→)가 켜져 있어야 동작합니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func row(_ action: MoveAction) -> some View {
        let binding = hotkeyBinding(for: action)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(action.label)
                Spacer()
                HotkeyCaptureView(hotkey: binding)
            }
            HotkeyConflictWarning(hotkey: binding.wrappedValue, selfId: nil)
        }
    }

    /// 해당 액션의 핫키에 대한 양방향 바인딩. 없으면 빈 바인딩을 만들어 둔다.
    private func hotkeyBinding(for action: MoveAction) -> Binding<HotkeyConfig?> {
        Binding(
            get: { store.moveBindings.first { $0.action == action }?.hotkey },
            set: { newValue in
                var list = store.moveBindings
                if let i = list.firstIndex(where: { $0.action == action }) {
                    list[i].hotkey = newValue
                } else {
                    list.append(MoveBinding(action: action, hotkey: newValue))
                }
                store.moveBindings = list
                hotkeys.registry.rebuild()
            }
        )
    }
}
