import Foundation

enum RaycastCommand: Equatable {
    case preset(UUID)
    case cycle(UUID)
    case layout(UUID)
    case move(MoveAction)
    case size(SizeAction)

    enum ParseError: Error {
        case invalidScheme
        case invalidVersion
        case invalidRoute
    }

    init(url: URL) throws {
        guard url.scheme == "my-window-manager" else {
            throw ParseError.invalidScheme
        }
        guard url.host == "v1" else {
            throw ParseError.invalidVersion
        }

        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 2 else {
            throw ParseError.invalidRoute
        }

        switch (parts[0], parts[1]) {
        case ("preset", let value):
            guard let id = UUID(uuidString: value) else { throw ParseError.invalidRoute }
            self = .preset(id)
        case ("cycle", let value):
            guard let id = UUID(uuidString: value) else { throw ParseError.invalidRoute }
            self = .cycle(id)
        case ("layout", let value):
            guard let id = UUID(uuidString: value) else { throw ParseError.invalidRoute }
            self = .layout(id)
        case ("move", "display-prev"):
            self = .move(.displayPrev)
        case ("move", "display-next"):
            self = .move(.displayNext)
        case ("move", "space-prev"):
            self = .move(.spacePrev)
        case ("move", "space-next"):
            self = .move(.spaceNext)
        case ("size", "grow"):
            self = .size(.grow)
        case ("size", "shrink"):
            self = .size(.shrink)
        default:
            throw ParseError.invalidRoute
        }
    }

    var url: URL {
        URL(string: "my-window-manager://v1/\(routeKind)/\(routeIdentifier)")!
    }

    var routeKind: String {
        switch self {
        case .preset: return "preset"
        case .cycle: return "cycle"
        case .layout: return "layout"
        case .move: return "move"
        case .size: return "size"
        }
    }

    var routeIdentifier: String {
        switch self {
        case .preset(let id), .cycle(let id), .layout(let id):
            return id.uuidString.lowercased()
        case .move(.displayPrev):
            return "display-prev"
        case .move(.displayNext):
            return "display-next"
        case .move(.spacePrev):
            return "space-prev"
        case .move(.spaceNext):
            return "space-next"
        case .size(.grow):
            return "grow"
        case .size(.shrink):
            return "shrink"
        }
    }
}
