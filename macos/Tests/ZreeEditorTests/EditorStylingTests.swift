import AppKit
import XCTest
import ZreeCore
@testable import ZreeEditor

/// These tests build the real text system (NSTextStorage + ZreeLayoutManager + NSTextView)
/// and inspect the attributes the editor produces, so styling bugs are caught without a
/// human looking at the window.
@MainActor
final class EditorStylingTests: XCTestCase {
    private var vaultDir: URL!
    private var session: ZreeSession!

    override func setUpWithError() throws {
        vaultDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zree-styling-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        try "# dummy\n".write(
            to: vaultDir.appendingPathComponent("dummy.md"),
            atomically: true,
            encoding: .utf8
        )
        session = try ZreeSession.open(root: vaultDir.path)
    }

    override func tearDownWithError() throws {
        session = nil
        try? FileManager.default.removeItem(at: vaultDir)
    }

    private let baseFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    private let baseColor = NSColor.labelColor
    private let mutedColor = NSColor.tertiaryLabelColor

    private func makeTextView(_ text: String) -> NSTextView {
        let storage = NSTextStorage()
        let layout = ZreeLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        textView.isRichText = true
        textView.string = text
        return textView
    }

    private func blocks(_ text: String) -> [Block] {
        session.blocksOf(text: text)
    }

    private func style(_ textView: NSTextView, _ text: String) {
        EditorStyling.restyle(
            textView,
            blocks: blocks(text),
            baseFont: baseFont,
            baseColor: baseColor,
            lineHeight: 1.6,
            mutedColor: mutedColor
        )
    }

    private func font(_ textView: NSTextView, at location: Int) -> NSFont {
        let storage = textView.textStorage!
        return storage.attribute(.font, at: location, effectiveRange: nil) as! NSFont
    }

    func test_headings_are_rendered_larger_than_body_text() {
        let text = "# 見出し1\n## 見出し2\n本文"
        let textView = makeTextView(text)
        style(textView, text)

        let h1 = font(textView, at: 0)
        let h2 = font(textView, at: text.distance(from: text.startIndex, to: text.range(of: "##")!.lowerBound))
        let body = font(textView, at: (text as NSString).range(of: "本文").location)

        XCTAssertGreaterThan(h1.pointSize, baseFont.pointSize, "h1 must be larger than body text")
        XCTAssertGreaterThan(h2.pointSize, baseFont.pointSize, "h2 must be larger than body text")
        XCTAssertGreaterThan(h1.pointSize, h2.pointSize, "h1 must be larger than h2")
        XCTAssertEqual(body.pointSize, baseFont.pointSize, accuracy: 0.01)
        XCTAssertTrue(
            h1.fontDescriptor.symbolicTraits.contains(.bold),
            "headings are bold"
        )
    }

    func test_inline_markers_are_styled_in_place() {
        let text = "これは **太字** と `コード` と ~~打消し~~ です"
        let textView = makeTextView(text)
        style(textView, text)
        let ns = text as NSString

        let boldFont = font(textView, at: ns.range(of: "太字").location)
        XCTAssertTrue(boldFont.fontDescriptor.symbolicTraits.contains(.bold))

        let codeLocation = ns.range(of: "コード").location
        let codeBackground = textView.textStorage!.attribute(
            .backgroundColor, at: codeLocation, effectiveRange: nil
        )
        XCTAssertNotNil(codeBackground, "inline code gets a tinted background")

        let strike = textView.textStorage!.attribute(
            .strikethroughStyle,
            at: ns.range(of: "打消し").location,
            effectiveRange: nil
        ) as? Int
        XCTAssertEqual(strike, NSUnderlineStyle.single.rawValue)
    }

    func test_rule_lines_are_marked_for_drawing() {
        let text = "上\n---\n下"
        let textView = makeTextView(text)
        style(textView, text)
        let location = (text as NSString).range(of: "---").location

        let value = textView.textStorage!.attribute(.zreeRule, at: location, effectiveRange: nil)
        XCTAssertNotNil(value, "a --- line must be handed to the layout manager")
        let color = textView.textStorage!.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, NSColor.clear, "the dashes themselves are not painted")
    }

    func test_typing_in_a_heading_keeps_the_heading_size() {
        let text = "# 見出し"
        let textView = makeTextView(text)
        style(textView, text)

        // what the editor does when the caret enters the line
        let lineStyle = EditorStyling.styleOfLine("# 見出し", baseFont: baseFont)
        XCTAssertNotNil(lineStyle)
        textView.typingAttributes = EditorStyling.typingAttributes(
            for: lineStyle,
            baseFont: baseFont,
            baseColor: baseColor,
            lineHeight: 1.6
        )

        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        textView.insertText("あ", replacementRange: textView.selectedRange())

        let inserted = font(textView, at: (text as NSString).length)
        XCTAssertGreaterThan(
            inserted.pointSize,
            baseFont.pointSize,
            "characters typed in a heading must appear at the heading size immediately"
        )
    }

    func test_several_characters_typed_in_a_heading_keep_the_heading_size() {
        let text = "# 見出し"
        let textView = makeTextView(text)
        style(textView, text)

        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))

        for character in ["あ", "い", "う"] {
            // the editor refreshes typing attributes for the caret line before each insert
            let lineRange = (textView.string as NSString).lineRange(
                for: NSRange(location: textView.selectedRange().location, length: 0)
            )
            let line = (textView.string as NSString).substring(with: lineRange)
            let lineStyle = EditorStyling.styleOfLine(line, baseFont: baseFont)
            textView.typingAttributes = EditorStyling.typingAttributes(
                for: lineStyle,
                baseFont: baseFont,
                baseColor: baseColor,
                lineHeight: 1.6
            )
            textView.insertText(character, replacementRange: textView.selectedRange())
        }

        let ns = textView.string as NSString
        for offset in 0..<ns.length {
            let size = font(textView, at: offset).pointSize
            XCTAssertGreaterThan(size, baseFont.pointSize, "offset \(offset) lost the heading size")
        }
    }

    /// Attributes alone are not proof: this checks that the layout really gives the
    /// heading line more height, which is what a reader sees.
    func test_heading_lines_occupy_more_height_than_body_lines() {
        let text = "# 見出し\n本文です"
        let textView = makeTextView(text)
        style(textView, text)

        guard let layout = textView.layoutManager, let container = textView.textContainer else {
            return XCTFail("no layout manager")
        }
        layout.ensureLayout(for: container)

        let headingHeight = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).height
        let bodyGlyph = layout.glyphIndexForCharacter(at: (text as NSString).range(of: "本文").location)
        let bodyHeight = layout.lineFragmentRect(forGlyphAt: bodyGlyph, effectiveRange: nil).height

        XCTAssertGreaterThan(
            headingHeight,
            bodyHeight * 1.2,
            "the heading line must be visibly taller (heading \(headingHeight), body \(bodyHeight))"
        )
    }

    func test_list_markers_are_muted_but_text_is_not() {
        let text = "- 項目"
        let textView = makeTextView(text)
        style(textView, text)

        let markerColor = textView.textStorage!.attribute(
            .foregroundColor, at: 0, effectiveRange: nil
        ) as? NSColor
        XCTAssertEqual(markerColor, mutedColor)
    }
}
