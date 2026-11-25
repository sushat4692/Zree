import AppKit
import ZreeCore
import ZreeEditor
import SwiftUI

/// Plain NSTextView: the most reliable Japanese IME path on macOS,
/// and it stays fast on long notes.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var lineHeight: Double
    @Environment(AppState.self) private var app

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.autohidesScrollers = true

        // a text system we control, so `---` lines can be drawn as real dividers
        let storage = NSTextStorage()
        let layoutManager = ZreeLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = ZreeTextView(frame: .zero, textContainer: container)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView

        context.coordinator.app = app
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        // Attributes are how the editor renders Markdown. With isRichText = false,
        // NSTextView ignores per-range fonts entirely (headings and bold silently did
        // nothing); the document stays plain because we write `textView.string` back
        // and drive typing through typingAttributes.
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = font
        textView.backgroundColor = ZreePalette.editorBackground
        textView.textColor = ZreePalette.editorText
        textView.insertionPointColor = NSColor(ZreePalette.accent)
        scroll.drawsBackground = true
        scroll.backgroundColor = ZreePalette.editorBackground
        // same margins as the preview pane
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.string = text
        context.coordinator.restyleWholeDocument(textView)

        return scroll
    }

    /// Toggling the preview pane rebuilds this view; without this the window's undo
    /// manager keeps registrations whose targets are about to be freed, which crashed
    /// in -[NSUndoManager undoNestedGroup] when ⌘Z was pressed afterwards.
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        (scroll.documentView as? NSTextView)?.undoManager?.removeAllActions()
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.app = app
        guard let textView = scroll.documentView as? NSTextView else { return }

        let fontChanged = context.coordinator.lastFont != font
            || context.coordinator.lastLineHeight != lineHeight
        applyTypography(to: textView)

        if textView.string != text {
            // Replacing the text behind the undo manager's back leaves it holding
            // ranges from the previous note; pressing ⌘Z then crashed in
            // -[NSUndoManager undoNestedGroup]. Loading a note is not an edit, so
            // drop the stack around the change.
            // Registrations from the previous note belong to this text view; drop them
            // so ⌘Z cannot pop a group pointing at the old storage.
            textView.undoManager?.removeAllActions()
            let selected = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(selected.location, text.utf16.count), length: 0))
            textView.undoManager?.removeAllActions()
            textView.breakUndoCoalescing()
            context.coordinator.restyleWholeDocument(textView)
        } else if fontChanged {
            context.coordinator.restyleWholeDocument(textView)
        } else {
            context.coordinator.refreshTypingAttributesForCurrentLine(textView)
        }
    }

    /// Fonts and line height are attributes only, so they never enter the undo stack.
    private func applyTypography(to textView: NSTextView) {
        // No `textView.font` here: that setter replaces the font of the whole text and
        // erased the rendering on every update.
        EditorStyling.applyDefaults(
            textView,
            baseFont: font,
            baseColor: ZreePalette.editorText,
            lineHeight: lineHeight,
            mutedColor: .tertiaryLabelColor
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: MarkdownEditor
        var app: AppState?

        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            handleEdit(textView)

            // Offer tag candidates while the caret sits in an @tag. Driven by the core's
            // context rather than by the last keystroke: NSTextView's word range excludes
            // `@`, and the panel also has to stay in sync while the prefix grows.
            if !textView.hasMarkedText() {
                let ns = textView.string as NSString
                let caret = textView.selectedRange().location
                if caret > 0, caret <= ns.length,
                   let app,
                   let ctx = app.completionContext(ns.substring(to: caret)),
                   ctx.kind == .tag {
                    textView.complete(nil)
                }
            }
        }

        @MainActor
        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard replacementString == "\n" else { return true }
            return !handleReturn(textView, at: affectedCharRange.location)
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            pendingEditRange = editedRange
        }

        @MainActor
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            handleCaretMove(textView)
        }

        /// Last block signature applied per line, so we only restyle when the kind changes.
        private var lineKinds: [Int: String] = [:]
        private var activeLineRange: NSRange?

        @MainActor
        private func kindSignature(_ textView: NSTextView, lineRange: NSRange) -> String {
            let ns = textView.string as NSString
            guard lineRange.location + lineRange.length <= ns.length else { return "blank" }
            let block = ZreeCore.lineBlock(line: ns.substring(with: lineRange))
            switch block {
            case .heading(let level, _, _): return "h\(level)"
            case .listItem: return "list"
            case .quote: return "quote"
            case .code: return "code"
            case .rule: return "rule"
            case .blank: return "blank"
            default: return "para"
            }
        }

        @MainActor
        private func lineRange(at location: Int, in textView: NSTextView) -> NSRange {
            let ns = textView.string as NSString
            let clamped = max(0, min(location, ns.length))
            return ns.lineRange(for: NSRange(location: clamped, length: 0))
        }

        /// Typing must continue in the font the caret currently sits in.
        @MainActor
        private func refreshTypingAttributes(_ textView: NSTextView) {
            let range = lineRange(at: textView.selectedRange().location, in: textView)
            let line = (textView.string as NSString).substring(with: range)
            let style = EditorStyling.styleOfLine(line, baseFont: parent.font)
            textView.typingAttributes = EditorStyling.typingAttributes(
                for: style,
                baseFont: parent.font,
                baseColor: ZreePalette.editorText,
                lineHeight: parent.lineHeight
            )
            activeLineRange = range
        }

        /// Style a line if its block kind is unknown or changed. This is the only place
        /// that runs a (single-line) parse while typing.
        @MainActor
        private func ensureStyled(_ textView: NSTextView, range: NSRange) {
            let signature = kindSignature(textView, lineRange: range)
            guard lineKinds[range.location] != signature else { return }
            lineKinds[range.location] = signature
            EditorStyling.restyleLine(
                textView,
                lineRange: range,
                baseFont: parent.font,
                baseColor: ZreePalette.editorText,
                lineHeight: parent.lineHeight,
                mutedColor: .tertiaryLabelColor
            )
        }

        /// After an edit: react only when the line's block kind actually changed.
        @MainActor
        private func handleEdit(_ textView: NSTextView) {
            let edited = pendingEditRange ?? textView.selectedRange()
            pendingEditRange = nil

            let range = lineRange(at: edited.location, in: textView)
            ensureStyled(textView, range: range)

            // Deleting at a boundary makes AppKit carry the previous line's attributes
            // into its neighbour (a bold heading turned the start of the next line bold),
            // so rebuild the neighbours unconditionally.
            repair(textView, range: lineRange(at: range.location + range.length, in: textView))

            if edited.location <= range.location {
                let previous = max(0, range.location - 1)
                repair(textView, range: lineRange(at: previous, in: textView))
            }

            refreshTypingAttributes(textView)
        }

        /// Re-apply a line's own styling, ignoring the cached kind.
        @MainActor
        private func repair(_ textView: NSTextView, range: NSRange) {
            let ns = textView.string as NSString
            guard range.length > 0, range.location + range.length <= ns.length else { return }
            lineKinds[range.location] = kindSignature(textView, lineRange: range)
            EditorStyling.restyleLine(
                textView,
                lineRange: range,
                baseFont: parent.font,
                baseColor: ZreePalette.editorText,
                lineHeight: parent.lineHeight,
                mutedColor: .tertiaryLabelColor
            )
        }

        /// Leaving a line is the moment to render its inline styling.
        @MainActor
        private func handleCaretMove(_ textView: NSTextView) {
            let newRange = lineRange(at: textView.selectedRange().location, in: textView)

            if let old = activeLineRange, old != newRange {
                let ns = textView.string as NSString
                if old.location + old.length <= ns.length {
                    EditorStyling.restyleLine(
                        textView,
                        lineRange: old,
                        baseFont: parent.font,
                        baseColor: ZreePalette.editorText,
                        lineHeight: parent.lineHeight,
                        mutedColor: .tertiaryLabelColor
                    )
                }
            }
            // the line we are entering must already look right, or the first character
            // would be typed at the wrong size
            ensureStyled(textView, range: newRange)
            refreshTypingAttributes(textView)
        }

        @MainActor
        func refreshTypingAttributesForCurrentLine(_ textView: NSTextView) {
            refreshTypingAttributes(textView)
        }

        var pendingEditRange: NSRange?
        var lastFont: NSFont?
        var lastLineHeight: Double?

        /// The document was replaced (note opened / changed on disk): parse it once.
        @MainActor
        func restyleWholeDocument(_ textView: NSTextView) {
            guard let app else { return }
            lineKinds.removeAll()
            lastFont = parent.font
            lastLineHeight = parent.lineHeight
            EditorStyling.restyle(
                textView,
                blocks: app.blocks(of: textView.string),
                baseFont: parent.font,
                baseColor: ZreePalette.editorText,
                lineHeight: parent.lineHeight,
                mutedColor: .tertiaryLabelColor
            )
            refreshTypingAttributes(textView)
        }

        @MainActor
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                return indent(textView, outdent: false)
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                return indent(textView, outdent: true)
            }
            return false
        }

        @MainActor
        func textView(
            _ textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            let candidates = completions(for: textView, range: charRange)
            if candidates.isEmpty { return words }
            index?.pointee = -1
            return candidates
        }
    }
}
