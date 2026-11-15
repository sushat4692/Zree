import AppKit
import ZreeCore

/// Toolbar actions for the editor. They operate on the focused NSTextView so the
/// undo stack stays coherent, and defer all decisions to the shared core.
enum EditorCommands {
    static func textView() -> NSTextView? {
        NSApp.keyWindow?.firstResponder as? NSTextView
    }

    private static func lineRange(_ textView: NSTextView) -> NSRange {
        let ns = textView.string as NSString
        let caret = min(textView.selectedRange().location, ns.length)
        let before = ns.substring(to: caret) as NSString
        let newline = before.range(of: "\n", options: .backwards)
        let start = newline.location == NSNotFound ? 0 : newline.location + 1
        let rest = ns.range(of: "\n", options: [], range: NSRange(location: caret, length: ns.length - caret))
        let end = rest.location == NSNotFound ? ns.length : rest.location
        return NSRange(location: start, length: end - start)
    }

    private static func rewriteLine(_ transform: (String) -> String) {
        guard let textView = textView() else { return }
        let range = lineRange(textView)
        let line = (textView.string as NSString).substring(with: range)
        let rewritten = transform(line)
        guard rewritten != line else { return }
        textView.insertText(rewritten, replacementRange: range)
        textView.setSelectedRange(NSRange(location: range.location + (rewritten as NSString).length, length: 0))
    }

    static func indent(outdent: Bool) {
        rewriteLine { ZreeCore.indentLine(line: $0, outdent: outdent) ?? $0 }
    }

    static func block(_ kind: BlockKind) {
        rewriteLine { ZreeCore.formatBlock(line: $0, kind: kind) }
    }

    static func toggleTask() {
        rewriteLine { ZreeCore.toggleTask(line: $0) }
    }

    /// Wrap or unwrap an inline marker. Offsets cross the FFI in characters.
    static func toggleInline(_ mark: String) {
        guard let textView = textView() else { return }
        let text = textView.string
        let selection = textView.selectedRange()
        let start16 = min(selection.location, (text as NSString).length)
        let end16 = min(selection.location + selection.length, (text as NSString).length)

        let result = ZreeCore.toggleInline(
            text: text,
            selStart: UInt32(scalarIndex(text, utf16: start16)),
            selEnd: UInt32(scalarIndex(text, utf16: end16)),
            mark: mark
        )

        let newStart = utf16Index(result.text, scalars: Int(result.selStart))
        let newEnd = utf16Index(result.text, scalars: Int(result.selEnd))
        apply(textView, text: result.text, selection: NSRange(location: newStart, length: newEnd - newStart))
    }

    /// Replace only the characters that actually changed.
    ///
    /// Replacing the whole document (the first version did) selects everything, scrolls
    /// to the caret and turns one bold toggle into a single huge undo step.
    private static func apply(_ textView: NSTextView, text newText: String, selection: NSRange) {
        let old = textView.string as NSString
        let new = newText as NSString
        let oldLength = old.length
        let newLength = new.length

        var prefix = 0
        let limit = min(oldLength, newLength)
        while prefix < limit, old.character(at: prefix) == new.character(at: prefix) {
            prefix += 1
        }
        var suffix = 0
        while suffix < limit - prefix,
              old.character(at: oldLength - 1 - suffix) == new.character(at: newLength - 1 - suffix) {
            suffix += 1
        }

        let range = NSRange(location: prefix, length: oldLength - prefix - suffix)
        let replacement = new.substring(
            with: NSRange(location: prefix, length: newLength - prefix - suffix)
        )
        if replacement.isEmpty && range.length == 0 { return }
        textView.insertText(replacement, replacementRange: range)
        textView.setSelectedRange(selection)
    }

    private static func utf16Index(_ text: String, scalars: Int) -> Int {
        var seen = 0
        var index = 0
        for scalar in text.unicodeScalars {
            if seen == scalars { break }
            index += UTF16.width(scalar)
            seen += 1
        }
        return index
    }

    private static func scalarIndex(_ text: String, utf16 target: Int) -> Int {
        var seen = 0
        var index = 0
        for scalar in text.unicodeScalars {
            if index >= target { break }
            index += UTF16.width(scalar)
            seen += 1
        }
        return seen
    }
}
