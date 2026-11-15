import AppKit
import SwiftUI
import NoteCore

struct PreviewView: View {
    @Environment(AppState.self) private var app

    private var blocks: [Block] {
        app.blocks(of: app.body)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    row(block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private func row(_ block: Block) -> some View {
        switch block {
        case .blank:
            Spacer().frame(height: 6)

        case let .heading(level, text, _):
            Text(app.attributed(text))
                .font(.system(size: headingSize(level), weight: .bold))
                .padding(.top, level <= 2 ? 8 : 4)

        case let .listItem(indent, ordered, checked, text, _):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker(ordered: ordered, checked: checked))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, alignment: .trailing)
                Text(app.attributed(text))
                    .strikethrough(checked == true)
                    .foregroundStyle(checked == true ? .secondary : .primary)
            }
            .padding(.leading, CGFloat(indent) * 16)

        case let .quote(text, _):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 3)
                Text(app.attributed(text))
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

        case let .code(_, text, _):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
            }
            .background(Color.secondary.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 6))

        case let .image(src, alt, _):
            if let image = loadImage(src) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 520)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Text(alt.isEmpty ? "[画像が見つかりません: \(src)]" : alt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case let .paragraph(text, _):
            Text(app.attributed(text))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func loadImage(_ src: String) -> NSImage? {
        guard let url = app.imageURL(for: src) else { return nil }
        return NSImage(contentsOf: url)
    }

    private func headingSize(_ level: UInt8) -> CGFloat {
        switch level {
        case 1: 24
        case 2: 20
        case 3: 17
        case 4: 15
        default: 14
        }
    }

    private func marker(ordered: Bool, checked: Bool?) -> String {
        if let checked { return checked ? "✓" : "☐" }
        return ordered ? "•" : "–"
    }
}
