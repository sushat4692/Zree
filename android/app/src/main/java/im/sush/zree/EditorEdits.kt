package im.sush.zree

import uniffi.zree_core.BlockKind
import uniffi.zree_core.ListAction
import uniffi.zree_core.formatBlock
import uniffi.zree_core.indentLine
import uniffi.zree_core.listAction
import uniffi.zree_core.toggleInline
import uniffi.zree_core.toggleTask

/**
 * Text plus selection, in UTF-16 units (what Kotlin strings and Compose use).
 */
data class EditText(val text: String, val selStart: Int, val selEnd: Int) {
    val caret: Int get() = selStart
    companion object {
        fun atEnd(text: String) = EditText(text, text.length, text.length)
    }
}

/**
 * Editor edits, kept free of Compose so they can be unit-tested on the JVM.
 *
 * The *decisions* still live in the Rust core (`listAction`, `indentLine`,
 * `formatBlock`, `toggleTask`, `toggleInline`); this object only performs the
 * string surgery and the UTF-16 offsets that the UI needs.
 */
object EditorEdits {
    /**
     * Line containing [caret]: `start` inclusive, `end` exclusive.
     *
     * Not an IntRange: an empty last line gives start == end, and `until` turns that into
     * an empty range whose `last` is end - 1, which produced `substring(19, 18)` and
     * crashed the toolbar buttons on the last line.
     */
    data class LineSpan(val start: Int, val end: Int) {
        val isEmpty: Boolean get() = start >= end
    }

    fun lineRange(text: String, caret: Int): LineSpan {
        val at = caret.coerceIn(0, text.length)
        val start = if (at == 0) 0 else text.lastIndexOf('\n', at - 1).let { if (it < 0) 0 else it + 1 }
        val end = text.indexOf('\n', at).let { if (it < 0) text.length else it }
        return LineSpan(start, maxOf(start, end))
    }

    /**
     * List continuation when Return was pressed.
     *
     * The check is "a newline appeared right before the caret", not "exactly one character
     * was inserted": Android IMEs apply a prediction at the same time (aaa -> AAA plus the
     * newline in one edit), which made the strict version skip the assist.
     */
    fun newline(old: EditText, next: EditText): EditText? {
        val text = next.text
        val caret = next.selStart.coerceIn(0, text.length)
        if (caret == 0 || text[caret - 1] != '\n') return null

        // the newline has to be new; a caret that was already after one is not a Return
        val oldCaret = old.selStart.coerceIn(0, old.text.length)
        if (oldCaret > 0 && old.text[oldCaret - 1] == '\n') return null

        val lineEnd = caret - 1
        val lineStart = if (lineEnd == 0) 0 else {
            text.lastIndexOf('\n', lineEnd - 1).let { if (it < 0) 0 else it + 1 }
        }
        val line = text.substring(lineStart, lineEnd)

        return when (val action = runCatching { listAction(line) }.getOrNull()) {
            is ListAction.Continue -> {
                val marker = action.marker
                val inserted = text.substring(0, caret) + marker + text.substring(caret)
                val c = caret + marker.length
                EditText(inserted, c, c)
            }
            is ListAction.Replace -> {
                // the newline Enter inserted goes away with the marker: the empty item
                // becomes one shallower marker (or disappears) instead of adding a line
                val replaced = text.substring(0, lineStart) + action.marker + text.substring(lineEnd + 1)
                val c = lineStart + action.marker.length
                EditText(replaced, c, c)
            }
            else -> null
        }
    }

    /** Tab (indent) / Shift-Tab (outdent) on a list line. */
    fun indent(current: EditText, outdent: Boolean): EditText =
        rewriteLine(current) { indentLine(it, outdent) ?: it }

    /** Bullet / ordered / task / heading / quote; the same block again removes it. */
    fun block(current: EditText, kind: BlockKind): EditText =
        rewriteLine(current) { formatBlock(it, kind) }

    /** Flip a task checkbox (or turn the line into one). */
    fun taskToggle(current: EditText): EditText =
        rewriteLine(current) { toggleTask(it) }

    /** Wrap or unwrap an inline marker such as `**`. */
    fun toggleInline(current: EditText, mark: String): EditText {
        val start = minOf(current.selStart, current.selEnd).coerceIn(0, current.text.length)
        val end = maxOf(current.selStart, current.selEnd).coerceIn(0, current.text.length)
        val cpStart = current.text.codePointCount(0, start)
        val cpEnd = current.text.codePointCount(0, end)

        val result = runCatching { toggleInline(current.text, cpStart.toUInt(), cpEnd.toUInt(), mark) }
            .getOrNull() ?: return current

        val a = utf16Index(result.text, result.selStart.toInt())
        val b = utf16Index(result.text, result.selEnd.toInt())
        return EditText(result.text, a, b)
    }

    private fun rewriteLine(current: EditText, transform: (String) -> String): EditText {
        val caret = current.selStart.coerceIn(0, current.text.length)
        val range = lineRange(current.text, caret)
        val line = current.text.substring(range.start, range.end)
        val rewritten = runCatching { transform(line) }.getOrNull() ?: return current
        if (rewritten == line) return current

        val text = current.text.substring(0, range.start) + rewritten + current.text.substring(range.end)
        val target = (caret + rewritten.length - line.length)
            .coerceIn(range.start, range.start + rewritten.length)
        return EditText(text, target, target)
    }

    /** Convert a code-point offset (what the core uses) to a UTF-16 index. */
    fun utf16Index(text: String, codePoints: Int): Int {
        var i = 0
        var n = 0
        while (n < codePoints && i < text.length) {
            i += Character.charCount(text.codePointAt(i))
            n++
        }
        return i
    }
}
