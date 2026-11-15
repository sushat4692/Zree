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
     * List continuation when Return was pressed: returns the assisted value, or
     * null when the edit is a plain newline and should be left to the field.
     */
    fun newline(old: EditText, next: EditText): EditText? {
        val caret = old.selStart.coerceIn(0, old.text.length)
        val inserted = next.text.length == old.text.length + 1 &&
            next.text == old.text.substring(0, caret) + "\n" + old.text.substring(caret)
        if (!inserted) return null

        val range = lineRange(old.text, caret)
        val line = old.text.substring(range.start, caret)
        return when (val action = runCatching { listAction(line) }.getOrNull()) {
            is ListAction.Continue -> {
                val marker = action.marker
                val text = old.text.substring(0, caret) + "\n" + marker + old.text.substring(caret)
                val c = caret + 1 + marker.length
                EditText(text, c, c)
            }
            is ListAction.Replace -> {
                val text = old.text.substring(0, range.start) + action.marker + old.text.substring(caret)
                val c = range.start + action.marker.length
                EditText(text, c, c)
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
