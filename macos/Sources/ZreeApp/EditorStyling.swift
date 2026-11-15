import AppKit
import ZreeCore

/// Styles the editor like a document, except for the line holding the caret.
///
/// This is the "live preview" compromise: every other line shows its structure
/// (headings larger and bold, list/quote markers muted, code dimmed) while the line
/// being edited is left as plain Markdown, so nothing gets in the way of typing.
///
/// Only text attributes change — never characters — so the caret, the IME and the
/// undo stack are untouched (undo registration is suspended while styling).
/// Attribute used to mark a line that should be drawn as a horizontal rule.
extension NSAttributedString.Key {
    static let zreeRule = NSAttributedString.Key("ZreeRule")
}

/// Draws a real horizontal line for `---` lines, without touching the characters.
final class ZreeLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.zreeRule, in: charRange, options: []) { value, range, _ in
            guard value != nil, let container = textContainers.first else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = self.boundingRect(forGlyphRange: glyphRange, in: container)
            let y = origin.y + rect.midY
            let path = NSBezierPath()
            path.move(to: NSPoint(x: origin.x, y: y))
            path.line(to: NSPoint(x: origin.x + container.size.width, y: y))
            path.lineWidth = 1
            NSColor.separatorColor.setStroke()
            path.stroke()
        }
    }
}

enum EditorStyling {
    struct Style {
        var font: NSFont
        var color: NSColor
        /// Range within the line that should look muted (list bullet, `#`, `>`, fences).
        var markerLength: Int = 0
        /// `---` lines are drawn as a divider instead of text.
        var isRule: Bool = false
    }

    static func restyle(
        _ textView: NSTextView,
        blocks: [Block],
        baseFont: NSFont,
        baseColor: NSColor,
        lineHeight: Double,
        mutedColor: NSColor
    ) {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        // never touch attributes mid-composition: the IME owns that range
        if textView.hasMarkedText() { return }

        let text = storage.string as NSString
        let caretLine = lineNumber(in: text, at: textView.selectedRange().location)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = max(0.8, lineHeight)
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .paragraphStyle: paragraph,
            .foregroundColor: baseColor,
        ]

        var styles: [Int: Style] = [:]
        for block in blocks { if let s = style(for: block, baseFont: baseFont) { styles[s.line] = s.style } }

        textView.undoManager?.disableUndoRegistration()
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: NSRange(location: 0, length: storage.length))

        var line = 1
        var index = 0
        while index <= text.length {
            let remainder = NSRange(location: index, length: text.length - index)
            let newline = text.range(of: "\n", options: [], range: remainder)
            let end = newline.location == NSNotFound ? text.length : newline.location
            let lineRange = NSRange(location: index, length: end - index)

            if line != caretLine, let style = styles[line], lineRange.length > 0 {
                if style.isRule {
                    // drawn by ZreeLayoutManager; keep the characters but make them invisible
                    storage.addAttribute(.zreeRule, value: true, range: lineRange)
                    storage.addAttribute(.foregroundColor, value: NSColor.clear, range: lineRange)
                } else {
                    storage.addAttribute(.font, value: style.font, range: lineRange)
                    if style.markerLength > 0 {
                        let markerLength = min(style.markerLength, lineRange.length)
                        storage.addAttribute(
                            .foregroundColor,
                            value: mutedColor,
                            range: NSRange(location: lineRange.location, length: markerLength)
                        )
                    }
                    if style.color != baseColor {
                        storage.addAttribute(.foregroundColor, value: style.color, range: lineRange)
                    }
                    applyInline(
                        storage,
                        line: text.substring(with: lineRange),
                        lineRange: lineRange,
                        baseFont: style.font
                    )
                }
            }

            if newline.location == NSNotFound { break }
            index = end + 1
            line += 1
        }

        storage.endEditing()
        textView.undoManager?.enableUndoRegistration()
    }

    private static func style(for block: Block, baseFont: NSFont) -> (line: Int, style: Style)? {
        switch block {
        case let .heading(level, text, line):
            let scale: CGFloat = switch level {
            case 1: 1.55
            case 2: 1.35
            case 3: 1.2
            default: 1.1
            }
            let font = NSFont(descriptor: baseFont.fontDescriptor, size: baseFont.pointSize * scale)
                ?? NSFont.boldSystemFont(ofSize: baseFont.pointSize * scale)
            let hashes = Int(level) + 1   // markers plus the space
            _ = text
            return (Int(line), Style(font: font, color: .labelColor, markerLength: hashes))

        case let .listItem(_, _, _, text, line):
            let marker = text.isEmpty ? 1 : 2   // "- " / "1. " — the muted part
            return (Int(line), Style(font: baseFont, color: .labelColor, markerLength: marker))

        case let .quote(_, line):
            return (Int(line), Style(font: baseFont, color: .secondaryLabelColor, markerLength: 1))

        case let .code(_, _, line):
            let font = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.95, weight: .regular)
            return (Int(line), Style(font: font, color: .secondaryLabelColor))

        case let .rule(line):
            return (Int(line), Style(font: baseFont, color: .clear, isRule: true))

        default:
            return nil
        }
    }

    /// Bold / italic / strike / inline code inside one line of the document.
    static func applyInline(
        _ storage: NSTextStorage,
        line: String,
        lineRange: NSRange,
        baseFont: NSFont
    ) {
        let spans = ZreeCore.inlineSpans(line: line)
        guard !spans.isEmpty else { return }

        let bold = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        let italic = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        let mono = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.95, weight: .regular)

        for span in spans {
            let start = utf16Index(in: line, byteOffset: Int(span.start))
            let end = utf16Index(in: line, byteOffset: Int(span.end))
            guard end > start else { continue }
            let range = NSRange(location: lineRange.location + start, length: end - start)

            switch span.kind {
            case .bold:
                storage.addAttribute(.font, value: bold, range: range)
            case .italic:
                storage.addAttribute(.font, value: italic, range: range)
            case .strike:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case .code:
                storage.addAttribute(.font, value: mono, range: range)
                storage.addAttribute(
                    .backgroundColor,
                    value: NSColor.secondaryLabelColor.withAlphaComponent(0.12),
                    range: range
                )
            }
        }
    }

    /// Byte offset (as the core reports it) to a UTF-16 index for the same string.
    static func utf16Index(in text: String, byteOffset: Int) -> Int {
        var bytes = 0
        var utf16 = 0
        for scalar in text.unicodeScalars {
            if bytes >= byteOffset { break }
            bytes += UTF8.width(scalar)
            utf16 += UTF16.width(scalar)
        }
        return utf16
    }

    /// 1-based line number of a UTF-16 offset.
    ///
    /// Counts newlines strictly *before* the caret: a newline at the caret means the
    /// caret already sits at the end of that line, which is where `.byLines` used to
    /// add a line and push the styling onto the wrong row.
    static func lineNumber(in text: NSString, at location: Int) -> Int {
        let clamped = max(0, min(location, text.length))
        guard clamped > 0 else { return 1 }

        var line = 1
        var index = 0
        while index < clamped {
            let found = text.range(
                of: "\n",
                options: [],
                range: NSRange(location: index, length: clamped - index)
            )
            if found.location == NSNotFound { break }
            line += 1
            index = found.location + 1
        }
        return line
    }
}
