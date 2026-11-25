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

    /// The bug that survived several rounds: `textView.font = ...` rewrites the font of
    /// the entire text, so the styling vanished on the next SwiftUI update.
    func test_styling_survives_the_view_defaults_being_applied_again() {
        let text = "# 見出し\n本文 **太字**"
        let textView = makeTextView(text)
        style(textView, text)
        let before = font(textView, at: 0).pointSize

        EditorStyling.applyDefaults(
            textView,
            baseFont: baseFont,
            baseColor: baseColor,
            lineHeight: 1.6,
            mutedColor: mutedColor
        )

        XCTAssertEqual(font(textView, at: 0).pointSize, before, "applying defaults must not rewrite fonts")
    }

    /// Renders the styled text to /tmp/zree-proof.png so a human (or an agent) can look at
    /// the actual pixels instead of trusting attributes.
    func test_render_proof_image() throws {
        let text = "# 見出し1\n本文です。**太字**と `code` と ~~打消し~~。\n## 見出し2\n- 箇条書き\n---\nおわり"
        let textView = makeTextView(text)
        style(textView, text)
        textView.frame = NSRect(x: 0, y: 0, width: 640, height: 260)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)

        guard let rep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) else {
            return XCTFail("no bitmap")
        }
        textView.cacheDisplay(in: textView.bounds, to: rep)
        let url = URL(fileURLWithPath: "/tmp/zree-proof.png")
        try rep.representation(using: .png, properties: [:])?.write(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    /// Deleting at the end of a heading made AppKit copy the heading's bold font onto the
    /// next line. The editor repairs the neighbouring line; this checks the repair.
    func test_neighbouring_line_is_repaired_after_attribute_bleed() {
        let text = "# 見出し\n- 載っている内容"
        let textView = makeTextView(text)
        style(textView, text)

        // simulate AppKit bleeding the heading attributes onto the next line
        let storage = textView.textStorage!
        let ns = text as NSString
        let nextLine = ns.lineRange(for: NSRange(location: ns.range(of: "- 載").location, length: 0))
        let headingFont = storage.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        storage.addAttribute(.font, value: headingFont, range: nextLine)
        XCTAssertTrue(
            (storage.attribute(.font, at: nextLine.location, effectiveRange: nil) as! NSFont)
                .fontDescriptor.symbolicTraits.contains(.bold)
        )

        EditorStyling.restyleLine(
            textView,
            lineRange: nextLine,
            baseFont: baseFont,
            baseColor: baseColor,
            lineHeight: 1.6,
            mutedColor: mutedColor
        )

        let repaired = storage.attribute(.font, at: nextLine.location, effectiveRange: nil) as! NSFont
        XCTAssertFalse(
            repaired.fontDescriptor.symbolicTraits.contains(.bold),
            "the list line must not stay bold"
        )
        XCTAssertEqual(repaired.pointSize, baseFont.pointSize, accuracy: 0.01)
    }

    func test_headings_get_space_above_and_below() {
        let text = "本文\n# 見出し\n本文"
        let textView = makeTextView(text)
        style(textView, text)
        let ns = text as NSString
        let headingLocation = ns.range(of: "# 見出し").location
        let paragraph = textView.textStorage!.attribute(
            .paragraphStyle, at: headingLocation, effectiveRange: nil
        ) as? NSParagraphStyle
        XCTAssertNotNil(paragraph)
        XCTAssertGreaterThan(paragraph?.paragraphSpacingBefore ?? 0, 0)
        XCTAssertGreaterThan(paragraph?.paragraphSpacing ?? 0, 0)
    }

    func test_body_lines_use_a_fixed_line_height_so_the_caret_matches() {
        let text = "本文です"
        let textView = makeTextView(text)
        style(textView, text)
        let paragraph = textView.textStorage!.attribute(
            .paragraphStyle, at: 0, effectiveRange: nil
        ) as? NSParagraphStyle
        XCTAssertEqual(paragraph?.minimumLineHeight ?? 0, paragraph?.maximumLineHeight ?? -1, accuracy: 0.01)
        XCTAssertEqual(paragraph?.lineHeightMultiple ?? 0, 0, accuracy: 0.01, "no multiple: it offsets the glyphs from the caret")
    }

    func test_completion_range_covers_the_whole_at_tag() {
        let text = "本文 @お客"
        let textView = ZreeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))

        let range = textView.rangeForUserCompletion
        let covered = (text as NSString).substring(with: range)
        XCTAssertEqual(covered, "@お客", "the partial word must include the @")

        // a bare @ is a zero-length prefix but still the whole token
        textView.string = "本文 @"
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        XCTAssertEqual((textView.string as NSString).substring(with: textView.rangeForUserCompletion), "@")
    }

    /// The tag bar writes through `insertText`, not by replacing the document, so the tag can
    /// be taken back with ⌘Z like any other typing.
    private final class UndoHost: NSObject, NSTextViewDelegate {
        let manager: UndoManager
        override init() {
            manager = UndoManager()
            super.init()
        }
        func undoManager(for view: NSTextView) -> UndoManager? { manager }
    }

    func test_a_suggested_tag_can_be_undone() throws {
        // the core reads the note from disk, so the fixture must be the real text
        try "@挨拶  \n本文\n".write(
            to: vaultDir.appendingPathComponent("dummy.md"),
            atomically: true,
            encoding: .utf8
        )
        let textView = ZreeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        textView.isRichText = true
        textView.allowsUndo = true
        let host = UndoHost()
        textView.delegate = host
        textView.string = "@挨拶  \n本文\n"
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        let insertion = try session.tagInsertion(id: "dummy.md", tag: "新規")
        // "@挨拶" is three UTF-16 units, so the tag lands before the two trailing spaces
        XCTAssertEqual(insertion?.location, 3)
        XCTAssertEqual(insertion?.text, " @新規")

        let at = Int(insertion!.location)
        textView.insertText(insertion!.text, replacementRange: NSRange(location: at, length: 0))
        XCTAssertEqual(textView.string, "@挨拶 @新規  \n本文\n")

        XCTAssertTrue(host.manager.canUndo, "the insertion must be undoable")
        host.manager.undo()
        XCTAssertEqual(textView.string, "@挨拶  \n本文\n")
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
