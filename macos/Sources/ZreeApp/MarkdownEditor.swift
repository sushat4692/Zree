import AppKit
import SwiftUI

/// Plain NSTextView: the most reliable Japanese IME path on macOS,
/// and it stays fast on long notes.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    @Environment(AppState.self) private var app

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true

        guard let textView = scroll.documentView as? NSTextView else { return scroll }
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
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.backgroundColor = ZreePalette.editorBackground
        textView.textColor = ZreePalette.editorText
        textView.insertionPointColor = NSColor(ZreePalette.accent)
        scroll.drawsBackground = true
        scroll.backgroundColor = ZreePalette.editorBackground
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.app = app
        guard let textView = scroll.documentView as? NSTextView else { return }
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(selected.location, text.utf16.count), length: 0))
        }
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
