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

    /// Candidates for the completion panel (`complete:`).
    @MainActor
    func completions(for textView: NSTextView, range: NSRange) -> [String] {
        guard let app = self.app else { return [] }
        let ns = textView.string as NSString
        let end = range.location + range.length
        guard end <= ns.length else { return [] }
        let before = ns.substring(to: end)
        guard let ctx = app.completionContext(before), ctx.kind == .tag else { return [] }
        return app.suggestTags(ctx.prefix, limit: 8)
    }
}
