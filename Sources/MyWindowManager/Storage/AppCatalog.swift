import AppKit
import Combine

struct InstalledApp: Identifiable, Hashable {
    var id: String { bundleId }
    let bundleId: String
    let name: String
    let url: URL
    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}

@MainActor
final class AppCatalog: ObservableObject {
    @Published private(set) var apps: [InstalledApp] = []

    init() {
        Task { await refresh() }
    }

    func refresh() async {
        let scanned = await Task.detached(priority: .utility) {
            Self.scan()
        }.value
        self.apps = scanned
    }

    nonisolated private static func scan() -> [InstalledApp] {
        let fm = FileManager.default
        let roots: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        var seen = Set<String>()
        var found: [InstalledApp] = []

        for root in roots {
            guard let it = fm.enumerator(at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsPackageDescendants, .skipsHiddenFiles]) else { continue }
            while let url = it.nextObject() as? URL {
                if url.pathExtension == "app" {
                    it.skipDescendants()
                    if let bid = bundleId(of: url), !seen.contains(bid) {
                        seen.insert(bid)
                        let name = url.deletingPathExtension().lastPathComponent
                        found.append(InstalledApp(bundleId: bid, name: name, url: url))
                    }
                }
            }
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated private static func bundleId(of url: URL) -> String? {
        Bundle(url: url)?.bundleIdentifier
    }

    func find(_ bundleId: String) -> InstalledApp? {
        apps.first { $0.bundleId == bundleId }
    }
}
