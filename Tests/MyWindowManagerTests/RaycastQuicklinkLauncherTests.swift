import Testing
import Foundation
@testable import MyWindowManager

struct RaycastQuicklinkLauncherTests {
    @Test func encodesQuicklinkArguments() throws {
        let id = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!
        let request = RaycastQuicklinkRequest(name: "Max", command: .preset(id))
        let components = try #require(
            URLComponents(url: request.helperURL, resolvingAgainstBaseURL: false)
        )

        #expect(components.scheme == "raycast")
        #expect(components.host == "extensions")
        #expect(components.path == "/devookim/my-window-manager/create-quicklink")

        let encoded = try #require(
            components.queryItems?.first(where: { $0.name == "arguments" })?.value
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: String]
        )
        #expect(object == [
            "name": "Max",
            "kind": "preset",
            "identifier": id.uuidString.lowercased(),
        ])
    }

    @Test func encodesFixedActionArguments() throws {
        let request = RaycastQuicklinkRequest(
            name: "다음 디스플레이로",
            command: .move(.displayNext)
        )
        let components = try #require(
            URLComponents(url: request.helperURL, resolvingAgainstBaseURL: false)
        )
        let encoded = try #require(
            components.queryItems?.first(where: { $0.name == "arguments" })?.value
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: String]
        )
        #expect(object["kind"] == "move")
        #expect(object["identifier"] == "display-next")
    }
}
