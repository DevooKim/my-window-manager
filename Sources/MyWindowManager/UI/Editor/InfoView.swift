import SwiftUI
import AppKit

/// "정보" tab — app icon, version, update check, and links.
/// Mirrors the centered About-panel layout used in My AltTab.
struct InfoView: View {
    private static func bundleString(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 160, height: 160)
            Text("My Window Manager")
                .font(.title2.bold())
            Text("버전 \(Self.bundleString("CFBundleShortVersionString")) (\(Self.bundleString("CFBundleVersion")))")
                .foregroundColor(.secondary)
            Button("업데이트 확인") {
                Updater.checkForUpdates(silent: false)
            }
            .padding(.top, 4)
            Link("GitHub",
                 destination: URL(string: "https://github.com/DevooKim/my-window-manager")!)
            Text(Self.bundleString("NSHumanReadableCopyright"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
