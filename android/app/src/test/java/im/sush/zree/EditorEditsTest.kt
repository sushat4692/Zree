package im.sush.zree

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import uniffi.zree_core.BlockKind

/**
 * Runs on the host JVM against the real Rust core (jna.library.path points at the
 * macOS build), so it covers the same wiring the device uses.
 */
class EditorEditsTest {

    private fun type(caret: Int, old: String, inserted: String): EditText =
        EditText(old.substring(0, caret) + inserted + old.substring(caret), caret + inserted.length, caret + inserted.length)

    private fun enter(text: String): EditText? =
        EditorEdits.newline(EditText.atEnd(text), type(text.length, text, "\n"))

    @Test
    fun return_continues_every_list_kind() {
        assertEquals("- あ\n- ", enter("- あ")!!.text)
        assertEquals("* あ\n* ", enter("* あ")!!.text)
        assertEquals("+ あ\n+ ", enter("+ あ")!!.text)
        assertEquals("  - あ\n  - ", enter("  - あ")!!.text)
        assertEquals("\t- あ\n\t- ", enter("\t- あ")!!.text)
        assertEquals("1. あ\n2. ", enter("1. あ")!!.text)
        assertEquals("10. あ\n11. ", enter("10. あ")!!.text)
        assertEquals("> あ\n> ", enter("> あ")!!.text)
        assertEquals("- [x] あ\n- [ ] ", enter("- [x] あ")!!.text)
    }

    @Test
    fun return_in_the_middle_keeps_the_rest() {
        val text = "#見出し\n- 一つ目\n- 二つ目"
        val caret = "#見出し\n- 一つ目".length       // end of the "- 一つ目" line
        val next = type(caret, text, "\n")
        val result = EditorEdits.newline(EditText(text, caret, caret), next)!!
        assertEquals("#見出し\n- 一つ目\n- \n- 二つ目", result.text)
        assertEquals(caret + 1 + "- ".length, result.caret)   // caret after the new marker
    }

    @Test
    fun return_on_empty_item_outdents_then_leaves_the_list() {
        // empty nested item outdents one level
        assertEquals("  - あ\n- ", EditorEdits.newline(EditText.atEnd("  - あ\n  - "), type("  - あ\n  - ".length, "  - あ\n  - ", "\n"))!!.text)
        assertEquals("- あ\n", EditorEdits.newline(EditText.atEnd("- あ\n- "), type("- あ\n- ".length, "- あ\n- ", "\n"))!!.text)
    }

    @Test
    fun return_in_a_paragraph_is_left_alone() {
        assertNull(enter("ただの段落"))
        assertNull(enter("# 見出し"))
    }

    @Test
    fun tab_indents_and_shift_tab_outdents() {
        assertEquals("  - あ", EditorEdits.indent(EditText.atEnd("- あ"), outdent = false).text)
        assertEquals("  - あ", EditorEdits.indent(EditText.atEnd("    - あ"), outdent = true).text)
        // not a list line: unchanged
        assertEquals("ただの段落", EditorEdits.indent(EditText.atEnd("ただの段落"), outdent = false).text)
    }

    @Test
    fun block_buttons_replace_and_toggle() {
        assertEquals("# foo", EditorEdits.block(EditText.atEnd("- foo"), BlockKind.HEADING).text)
        assertEquals("foo", EditorEdits.block(EditText.atEnd("# foo"), BlockKind.HEADING).text)
        assertEquals("- [ ] foo", EditorEdits.block(EditText.atEnd("- foo"), BlockKind.TASK).text)
        assertEquals("1. foo", EditorEdits.block(EditText.atEnd("foo"), BlockKind.ORDERED).text)
        assertEquals("> foo", EditorEdits.block(EditText.atEnd("1. foo"), BlockKind.QUOTE).text)
    }

    @Test
    fun checkbox_toggle_flips_and_creates() {
        assertEquals("- [x] foo", EditorEdits.taskToggle(EditText.atEnd("- [ ] foo")).text)
        assertEquals("- [ ] foo", EditorEdits.taskToggle(EditText.atEnd("- [x] foo")).text)
        assertEquals("- [ ] foo", EditorEdits.taskToggle(EditText.atEnd("foo")).text)
    }

    @Test
    fun bold_toggles_instead_of_stacking() {
        val once = EditorEdits.toggleInline(EditText.atEnd("foo"), "**")
        assertEquals("foo****", once.text)
        val twice = EditorEdits.toggleInline(once, "**")
        assertEquals("foo", twice.text)

        val wrapped = EditorEdits.toggleInline(EditText("foo", 0, 3), "**")
        assertEquals("**foo**", wrapped.text)
        assertEquals("foo", EditorEdits.toggleInline(wrapped, "**").text)
    }

    @Test
    fun offsets_survive_emoji() {
        val text = "😀 foo"
        val cpIndex = EditorEdits.utf16Index(text, 1)
        assertEquals(2, cpIndex)   // one emoji is two UTF-16 units
        assertEquals("😀**** foo", EditorEdits.toggleInline(EditText(text, 2, 2), "**").text)
    }

    @Test
    fun line_range_handles_first_and_last_line() {
        assertEquals(0 until 3, EditorEdits.lineRange("abc\ndef", 2))
        assertEquals(4 until 7, EditorEdits.lineRange("abc\ndef", 5))
        assertEquals(0 until 0, EditorEdits.lineRange("", 0))
    }
}
