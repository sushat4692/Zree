import AppKit
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

        let textView = NSTextView(frame: .zero)
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

    final class Coordinator: NSObject, NSTextViewDelegate {
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
