import AppKit
import SwiftUI
import ZreeCore

struct PreviewView: View {
    @Environment(AppState.self) private var app

    private var blocks: [Block] {
        app.blocks(of: app.body)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    row(block)
                }
            }
            // a readable measure instead of one very long line on a wide window
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .textSelection(.enabled)
            .font(app.previewFont)
            .lineSpacing(app.previewLineSpacing)
        }
        .background(Color(nsColor: ZreePalette.editorBackground))
        .environment(\.openURL, OpenURLAction { url in
            app.openNoteLink(url) ? .handled : .systemAction
        })
    }

    @ViewBuilder
    private func row(_ block: Block) -> some View {
        switch block {
        case .blank:
            Spacer().frame(height: app.previewFontSize * 0.55)

        case let .heading(level, text, _):
            Text(app.attributed(text))
                .font(.system(size: headingSize(level), weight: level <= 2 ? .bold : .semibold))
                .lineSpacing(app.previewFontSize * 0.15)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, headingTopPadding(level))
                .padding(.bottom, level <= 2 ? 4 : 2)

        case let .listItem(indent, ordered, checked, text, _):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(marker(ordered: ordered, checked: checked))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 15, alignment: .trailing)
                Text(app.attributed(text))
                    .lineSpacing(app.previewLineSpacing * 0.6)
                    .strikethrough(checked == true)
                    .foregroundStyle(checked == true ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 18)
            .padding(.top, 1)

        case let .quote(text, _):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 3)
                Text(app.attributed(text))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 3)

        case let .code(_, text, _):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(size: max(11, app.previewFontSize - 3), design: .monospaced))
                    .lineSpacing(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .textSelection(.enabled)
            }
            .background(Color.secondary.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .padding(.vertical, 5)

        case let .image(src, alt, _):
            Group {
                if let image = loadImage(src) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 560)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Text(alt.isEmpty ? "[画像が見つかりません: \(src)]" : alt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 5)

        case let .paragraph(text, _):
            Text(app.attributed(text))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 1)
        }
    }

    private func loadImage(_ src: String) -> NSImage? {
        guard let url = app.imageURL(for: src) else { return nil }
        return NSImage(contentsOf: url)
    }

    private func headingSize(_ level: UInt8) -> CGFloat {
        switch level {
        case 1: app.previewFontSize * 1.85
        case 2: app.previewFontSize * 1.5
        case 3: app.previewFontSize * 1.22
        case 4: app.previewFontSize * 1.08
        default: app.previewFontSize
        }
    }

    private func headingTopPadding(_ level: UInt8) -> CGFloat {
        switch level {
        case 1: app.previewFontSize * 1.1
        case 2: app.previewFontSize * 0.8
        default: app.previewFontSize * 0.5
        }
    }

    private func marker(ordered: Bool, checked: Bool?) -> String {
        if let checked { return checked ? "✓" : "☐" }
        return ordered ? "•" : "–"
    }
}
