import SwiftUI

/// "이동·크기" 탭 — 포커스 창을 인접 디스플레이/스페이스로 옮기는 액션과
/// 창 확대/축소 액션의 핫키 설정.
struct MoveView: View {
    @EnvironmentObject var store: ConfigStore

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
            Section {
                sizeRow(.grow)
                sizeRow(.shrink)
                HStack {
                    Text("확대/축소 비율")
                    Spacer()
                    Text("\(stepPercent.wrappedValue)%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper("", value: stepPercent, in: 2...30, step: 1)
                        .labelsHidden()
                }
            } header: {
                Text("창 크기")
            } footer: {
                Text("한 번 누를 때마다 화면 크기의 위 비율만큼 창이 커지거나 작아집니다. 기준점은 창 중심입니다.")
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
                RaycastQuicklinkButton(
                    name: action.label,
                    command: .move(action),
                    compact: true
                )
                HotkeyCaptureView(hotkey: binding)
            }
            HotkeyConflictWarning(hotkey: binding.wrappedValue, selfId: nil)
        }
    }

    @ViewBuilder
    private func sizeRow(_ action: SizeAction) -> some View {
        let binding = sizeHotkeyBinding(for: action)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(action.label)
                Spacer()
                RaycastQuicklinkButton(
                    name: action.label,
                    command: .size(action),
                    compact: true
                )
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
            }
        )
    }

    private func sizeHotkeyBinding(for action: SizeAction) -> Binding<HotkeyConfig?> {
        Binding(
            get: { store.sizeBindings.first { $0.action == action }?.hotkey },
            set: { newValue in
                var list = store.sizeBindings
                if let i = list.firstIndex(where: { $0.action == action }) {
                    list[i].hotkey = newValue
                } else {
                    list.append(SizeBinding(action: action, hotkey: newValue))
                }
                store.sizeBindings = list
            }
        )
    }

    /// sizeStepRatio(0.02~0.30)를 % 정수로 노출.
    private var stepPercent: Binding<Int> {
        Binding(
            get: { Int((store.sizeStepRatio * 100).rounded()) },
            set: { store.sizeStepRatio = Double($0) / 100 }
        )
    }
}
