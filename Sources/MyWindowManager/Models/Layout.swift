import Foundation

enum DisplayMatcher: Codable, Hashable {
    case primary
    case index(Int)
    case name(String)

    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable { case primary, index, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .type)
        switch kind {
        case .primary:
            self = .primary
        case .index:
            self = .index(try c.decode(Int.self, forKey: .value))
        case .name:
            self = .name(try c.decode(String.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .primary:
            try c.encode(Kind.primary, forKey: .type)
        case .index(let i):
            try c.encode(Kind.index, forKey: .type)
            try c.encode(i, forKey: .value)
        case .name(let s):
            try c.encode(Kind.name, forKey: .type)
            try c.encode(s, forKey: .value)
        }
    }

    var displayString: String {
        switch self {
        case .primary: return "Primary"
        case .index(let i): return "Display \(i + 1)"
        case .name(let n): return n
        }
    }
}

enum LaunchTarget: Codable, Hashable {
    case none
    case path(String)
    case url(String)

    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable { case none, path, url }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .type)
        switch kind {
        case .none: self = .none
        case .path: self = .path(try c.decode(String.self, forKey: .value))
        case .url:  self = .url(try c.decode(String.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try c.encode(Kind.none, forKey: .type)
        case .path(let p):
            try c.encode(Kind.path, forKey: .type)
            try c.encode(p, forKey: .value)
        case .url(let u):
            try c.encode(Kind.url, forKey: .type)
            try c.encode(u, forKey: .value)
        }
    }

    var displayString: String {
        switch self {
        case .none: return ""
        case .path(let p): return p
        case .url(let u): return u
        }
    }
}

struct AppPlacement: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var bundleId: String
    var displayMatcher: DisplayMatcher
    var frame: RelativeFrame
    var launchIfNeeded: Bool = true
    var target: LaunchTarget = .none

    enum CodingKeys: String, CodingKey {
        case id, bundleId, displayMatcher, frame, launchIfNeeded, target
    }

    init(id: UUID = UUID(),
         bundleId: String,
         displayMatcher: DisplayMatcher,
         frame: RelativeFrame,
         launchIfNeeded: Bool = true,
         target: LaunchTarget = .none) {
        self.id = id
        self.bundleId = bundleId
        self.displayMatcher = displayMatcher
        self.frame = frame
        self.launchIfNeeded = launchIfNeeded
        self.target = target
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.bundleId = try c.decode(String.self, forKey: .bundleId)
        self.displayMatcher = try c.decode(DisplayMatcher.self, forKey: .displayMatcher)
        self.frame = try c.decode(RelativeFrame.self, forKey: .frame)
        self.launchIfNeeded = try c.decodeIfPresent(Bool.self, forKey: .launchIfNeeded) ?? true
        self.target = try c.decodeIfPresent(LaunchTarget.self, forKey: .target) ?? .none
    }
}

struct Layout: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var placements: [AppPlacement]
    var hotkey: HotkeyConfig?
}
