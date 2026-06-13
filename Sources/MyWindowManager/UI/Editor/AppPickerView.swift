import SwiftUI
import AppKit

struct AppPickerView: View {
    @EnvironmentObject var catalog: AppCatalog
    @Binding var selectedBundleId: String
    @State private var search: String = ""
    @State private var showing = false

    var current: InstalledApp? { catalog.find(selectedBundleId) }

    var body: some View {
        Button(action: { showing.toggle() }) {
            HStack {
                if let app = current {
                    Image(nsImage: app.icon).resizable().frame(width: 18, height: 18)
                    Text(app.name)
                } else {
                    Text(selectedBundleId.isEmpty ? "앱 선택..." : selectedBundleId)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.down").font(.caption)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing) {
            VStack(spacing: 0) {
                TextField("검색", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(8)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered) { app in
                            Button(action: {
                                selectedBundleId = app.bundleId
                                showing = false
                            }) {
                                HStack {
                                    Image(nsImage: app.icon)
                                        .resizable().frame(width: 20, height: 20)
                                    VStack(alignment: .leading) {
                                        Text(app.name)
                                        Text(app.bundleId).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: 340, height: 360)
            }
        }
    }

    private var filtered: [InstalledApp] {
        guard !search.isEmpty else { return catalog.apps }
        return catalog.apps.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.bundleId.localizedCaseInsensitiveContains(search)
        }
    }
}
