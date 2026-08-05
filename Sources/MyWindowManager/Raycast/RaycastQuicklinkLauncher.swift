import AppKit

struct RaycastQuicklinkRequest {
    let name: String
    let command: RaycastCommand

    var helperURL: URL {
        var components = URLComponents()
        components.scheme = "raycast"
        components.host = "extensions"
        components.path = "/devookim/my-window-manager/create-quicklink"

        let arguments = [
            "name": name,
            "kind": command.routeKind,
            "identifier": command.routeIdentifier,
        ]
        let data = try! JSONSerialization.data(
            withJSONObject: arguments,
            options: [.sortedKeys]
        )
        components.queryItems = [
            URLQueryItem(
                name: "arguments",
                value: String(decoding: data, as: UTF8.self)
            ),
        ]
        return components.url!
    }
}

@MainActor
enum RaycastQuicklinkLauncher {
    @discardableResult
    static func open(
        name: String,
        command: RaycastCommand,
        openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) },
        copyString: (String) -> Void = { value in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
    ) -> Bool {
        copyString(command.url.absoluteString)
        let request = RaycastQuicklinkRequest(name: name, command: command)
        guard openURL(request.helperURL) else {
            let alert = NSAlert()
            alert.messageText = "Raycast를 열 수 없습니다"
            alert.informativeText = "앱 링크를 클립보드에 복사했습니다. Raycast와 My Window Manager helper 익스텐션을 설치한 뒤 직접 Quicklink를 만들어주세요."
            alert.alertStyle = .warning
            alert.runModal()
            return false
        }
        return true
    }
}
