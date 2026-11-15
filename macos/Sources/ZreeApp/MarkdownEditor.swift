import AppKit
import ZreeCore
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

        let textView = NSTextView(frame: .zero, textContainer: container)
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
        textView.isRichText = false
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
        applyTypography(to: textView)
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
        }
    }

    /// Fonts and line height are attributes only, so they never enter the undo stack.
    private func applyTypography(to textView: NSTextView) {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = max(0.8, lineHeight)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: style,
            .foregroundColor: ZreePalette.editorText,
        ]

        textView.font = font
        textView.defaultParagraphStyle = style
        textView.typingAttributes = attributes

        guard let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        if full.length == 0 { return }

        let needsUpdate: Bool = {
            guard let current = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else { return true }
            return current != font
        }()
        guard needsUpdate else { return }

        storage.beginEditing()
        storage.setAttributes(attributes, range: full)
        storage.endEditing()
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

            // offer tag candidates right after the user types '#'
            let ns = textView.string as NSString
            let caret = textView.selectedRange().location
            if caret > 0, caret <= ns.length {
                let previous = ns.substring(with: NSRange(location: caret - 1, length: 1))
                if previous == "#" || previous == "＃" {
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

        /// After an edit: only react when the line's block kind actually changed.
        @MainActor
        private func handleEdit(_ textView: NSTextView) {
            let edited = pendingEditRange ?? textView.selectedRange()
            pendingEditRange = nil

            let range = lineRange(at: edited.location, in: textView)
            let signature = kindSignature(textView, lineRange: range)
            let index = range.location

            if lineKinds[index] != signature {
                lineKinds[index] = signature
                EditorStyling.restyleLine(
                    textView,
                    lineRange: range,
                    baseFont: parent.font,
                    baseColor: ZreePalette.editorText,
                    lineHeight: parent.lineHeight,
                    mutedColor: .tertiaryLabelColor
                )
            }
            refreshTypingAttributes(textView)
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
            refreshTypingAttributes(textView)
        }

        var pendingEditRange: NSRange?

        /// The document was replaced (note opened / changed on disk): parse it once.
        @MainActor
        func restyleWholeDocument(_ textView: NSTextView) {
            guard let app else { return }
            lineKinds.removeAll()
            EditorStyling.restyle(
                textView,
                app: app,
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
