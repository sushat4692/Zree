import AppKit
import ZreeCore

/// Return-key list continuation and tag completion.
///
/// The decisions come from the shared core (`listAction`, `completionContext`,
/// `suggestTags`) so macOS and Android behave identically; this type only wires
/// them into AppKit.
extension MarkdownEditor.Coordinator {
    /// Returns true when the edit was handled here.
    @MainActor
    func handleReturn(_ textView: NSTextView, at location: Int) -> Bool {
        let ns = textView.string as NSString
        guard location <= ns.length else { return false }

        let before = ns.substring(to: location)
        let lineStart = (before as NSString).range(of: "\n", options: .backwards)
        let start = lineStart.location == NSNotFound ? 0 : lineStart.location + 1
        let line = (before as NSString).substring(from: start)

        guard let app = self.app else { return false }
        switch app.listAction(line) {
        case .continue(let marker):
            textView.insertText("\n" + marker, replacementRange: NSRange(location: location, length: 0))
            return true

        case .replace(let marker):
            // empty item: outdent one level, or drop the marker at the left margin
            let range = NSRange(location: start, length: location - start)
            textView.insertText(marker, replacementRange: range)
            return true

        default:
            return false
        }
    }

    /// Tab indents a list line, Shift-Tab outdents it.
    @MainActor
    func indent(_ textView: NSTextView, outdent: Bool) -> Bool {
        guard let app = self.app else { return false }
        let ns = textView.string as NSString
        let caret = textView.selectedRange().location
        guard caret <= ns.length else { return false }

        let before = ns.substring(to: caret)
        let newlineBefore = (before as NSString).range(of: "\n", options: .backwards)
        let lineStart = newlineBefore.location == NSNotFound ? 0 : newlineBefore.location + 1

        var lineEnd = ns.length
        let after = ns.range(of: "\n", options: [], range: NSRange(location: caret, length: ns.length - caret))
        if after.location != NSNotFound { lineEnd = after.location }

        let line = ns.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart))
        guard let rewritten = app.indentLine(line, outdent: outdent) else { return false }

        let delta = (rewritten as NSString).length - (line as NSString).length
        textView.insertText(rewritten, replacementRange: NSRange(location: lineStart, length: lineEnd - lineStart))
        let target = max(lineStart, min(caret + delta, lineStart + (rewritten as NSString).length))
        textView.setSelectedRange(NSRange(location: target, length: 0))
        return true
    }

    /// Candidates for the completion panel (`complete:`).
    @MainActor
    func completions(for textView: NSTextView, range: NSRange) -> [String] {
        guard let app = self.app else { return [] }
        let ns = textView.string as NSString
        let end = range.location + range.length
        guard end <= ns.length else { return [] }
        let before = ns.substring(to: end)
        guard let ctx = app.completionContext(before), ctx.kind == .tag else { return [] }
        // the range covers `@prefix`, so candidates replace it completely
        return app.suggestTags(ctx.prefix, limit: 8).map { "@" + $0 }
    }
}
