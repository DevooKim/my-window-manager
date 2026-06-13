import SwiftUI

/// One preset entry shown in the cycle HUD.
struct HUDItem: Identifiable {
    let id = UUID()
    let name: String
    let frame: RelativeFrame
}

/// The centered HUD overlay shown while cycling. Dark vibrancy card with the
/// cycle name and either a vertical list or a row of position thumbnails,
/// highlighting the currently applied preset.
struct CycleHUDView: View {
    let cycleName: String
    let items: [HUDItem]
    let currentIndex: Int
    let style: CycleHUDStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            switch style {
            case .list: listBody
            case .thumbnails: thumbnailBody
            case .off: EmptyView()
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(cycleName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer(minLength: 16)
            Text("\(currentIndex + 1)/\(items.count)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }

    private var listBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                Text(item.name)
                    .font(.system(size: 13))
                    .foregroundStyle(idx == currentIndex ? Color.white : Color.white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(idx == currentIndex ? Color.accentColor.opacity(0.35) : .clear)
                    )
            }
        }
        .frame(minWidth: 180)
    }

    private var thumbnailBody: some View {
        HStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                PresetThumbnail(frame: item.frame, highlighted: idx == currentIndex)
            }
        }
    }
}
