import SwiftUI

struct RaycastQuicklinkButton: View {
    let name: String
    let command: RaycastCommand
    var beforeOpen: () -> Void = {}
    var compact = false

    var body: some View {
        Button {
            beforeOpen()
            RaycastQuicklinkLauncher.open(name: name, command: command)
        } label: {
            if compact {
                Image(systemName: "sparkles")
            } else {
                Label("Raycast에 추가", systemImage: "sparkles")
            }
        }
        .help("Raycast Quicklink 생성 화면 열기")
    }
}

struct RaycastQuicklinkRenameHint: View {
    var body: some View {
        Text("이름을 변경하면 기존 Raycast Quicklink 이름도 직접 변경해야 합니다.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
