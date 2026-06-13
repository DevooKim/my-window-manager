import Foundation

/// Minimal semantic version for update comparison. Parses "1.2.3" or
/// "v1.2.3"; missing components default to 0.
struct SemanticVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var nums = [0, 0, 0]
        for (i, part) in parts.enumerated() {
            guard let n = Int(part), n >= 0 else { return nil }
            nums[i] = n
        }
        self.init(major: nums[0], minor: nums[1], patch: nums[2])
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var description: String { "\(major).\(minor).\(patch)" }
}
