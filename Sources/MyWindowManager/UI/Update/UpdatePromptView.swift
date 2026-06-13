import SwiftUI
import AppKit

/// SwiftUI sheet body for the updater. Renders the GitHub release notes
/// (Markdown) natively so headings, lists, and links display formatted and
/// follow the system appearance (light/dark) without manual color handling.
struct UpdatePromptView: View {
    enum Action {
        case update   // "지금 업데이트"
        case dismiss  // "나중에" / "확인" / 창 닫기
    }

    enum Kind {
        /// An update is available and the user is offered to install it.
        case available(from: SemanticVersion, to: SemanticVersion)
    }

    let kind: Kind
    let notes: String
    /// Called exactly once with the user's choice; the window closes after.
    let onAction: (Action) -> Void

    private var title: String {
        switch kind {
        case let .available(_, to): return "버전 \(to.description)을(를) 사용할 수 있습니다"
        }
    }

    private var subtitle: String {
        switch kind {
        case let .available(from, to): return "현재 \(from.description) → \(to.description)"
        }
    }

    /// One rendered Markdown line. SwiftUI's `Text` only renders *inline*
    /// Markdown, so we split the body into lines ourselves and turn block
    /// syntax (`#` headings, `-`/`*` bullets) into styled rows, parsing the
    /// remaining inline syntax (bold, links, code) per line.
    private struct Line: Identifiable {
        let id = UUID()
        let text: AttributedString
        let font: Font
        let isBullet: Bool
        let topPadding: CGFloat
    }

    private func inline(_ s: Substring) -> AttributedString {
        (try? AttributedString(markdown: String(s))) ?? AttributedString(String(s))
    }

    private var lines: [Line] {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: "\n", omittingEmptySubsequences: false).map { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)[...]
            if line.hasPrefix("### ") {
                return Line(text: inline(line.dropFirst(4)), font: .subheadline.bold(), isBullet: false, topPadding: 8)
            }
            if line.hasPrefix("## ") {
                return Line(text: inline(line.dropFirst(3)), font: .headline, isBullet: false, topPadding: 10)
            }
            if line.hasPrefix("# ") {
                return Line(text: inline(line.dropFirst(2)), font: .title3.bold(), isBullet: false, topPadding: 10)
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                return Line(text: inline(line.dropFirst(2)), font: .body, isBullet: true, topPadding: 0)
            }
            return Line(text: inline(line), font: .body, isBullet: false, topPadding: 0)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(lines) { line in
                        if line.isBullet {
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                Text(line.text)
                            }
                            .font(line.font)
                        } else {
                            Text(line.text)
                                .font(line.font)
                                .padding(.top, line.topPadding)
                        }
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .frame(height: 240)
            .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            buttons
        }
        .padding(20)
        .frame(width: 420)
        // 설정창과 동일한 behind-window vibrancy. 위에 얹힌 텍스트가 흐려지지
        // 않게 disablesVibrancy, 포커스 잃으면 불투명해지게 followsWindowActiveState.
        // 설정창과 동일한 behind-window vibrancy. 투명 창은 시스템 모서리 마스크가
        // 안 먹으므로 VisualEffectView가 호스트 contentView 전체(타이틀바 영역 포함)를
        // 둥글게 클립해 설정창과 같은 윈도우 radius로 통일한다.
        .background(
            VisualEffectView(
                material: .hudWindow,
                state: .followsWindowActiveState,
                makesHostWindowTransparent: true,
                disablesVibrancy: true,
                hostWindowCornerRadius: 10
            )
            .ignoresSafeArea()
        )
    }

    private var buttons: some View {
        HStack {
            Button("나중에") { onAction(.dismiss) }
                .keyboardShortcut(.cancelAction)
            Button("지금 업데이트") { onAction(.update) }
                .keyboardShortcut(.defaultAction)
        }
    }
}
