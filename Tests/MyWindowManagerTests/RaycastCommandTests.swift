import Testing
import Foundation
@testable import MyWindowManager

struct RaycastCommandTests {
    private let id = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!

    @Test func parsesEverySupportedRoute() throws {
        #expect(try RaycastCommand(url: URL(string: "my-window-manager://v1/preset/\(id.uuidString)")!) == .preset(id))
        #expect(try RaycastCommand(url: URL(string: "my-window-manager://v1/cycle/\(id.uuidString)")!) == .cycle(id))
        #expect(try RaycastCommand(url: URL(string: "my-window-manager://v1/layout/\(id.uuidString)")!) == .layout(id))
        #expect(try RaycastCommand(url: URL(string: "my-window-manager://v1/move/display-next")!) == .move(.displayNext))
        #expect(try RaycastCommand(url: URL(string: "my-window-manager://v1/move/space-prev")!) == .move(.spacePrev))
        #expect(try RaycastCommand(url: URL(string: "my-window-manager://v1/size/grow")!) == .size(.grow))
    }

    @Test func serializesAndParsesRoundTrip() throws {
        let commands: [RaycastCommand] = [
            .preset(id), .cycle(id), .layout(id),
            .move(.displayPrev), .move(.displayNext),
            .move(.spacePrev), .move(.spaceNext),
            .size(.grow), .size(.shrink),
        ]
        for command in commands {
            #expect(try RaycastCommand(url: command.url) == command)
        }
    }

    @Test func rejectsInvalidRoutes() {
        let invalid = [
            "https://v1/preset/\(id.uuidString)",
            "my-window-manager://v2/preset/\(id.uuidString)",
            "my-window-manager://v1/preset/not-a-uuid",
            "my-window-manager://v1/move/unknown",
            "my-window-manager://v1/size/grow/extra",
        ]
        for value in invalid {
            #expect(throws: RaycastCommand.ParseError.self) {
                try RaycastCommand(url: URL(string: value)!)
            }
        }
    }
}
