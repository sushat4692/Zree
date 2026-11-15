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
        let whole = NSRange(location: 0, length: (textView.string as NSString).length)
        textView.insertText(result.text, replacementRange: whole)
        textView.setSelectedRange(NSRange(location: newStart, length: newEnd - newStart))
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
