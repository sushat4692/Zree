package im.sush.zree

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.sp
import uniffi.zree_core.SpanKind
import uniffi.zree_core.inlineSpans
import uniffi.zree_core.lineBlock

/**
 * Renders Markdown in place, like the macOS editor: headings larger and bold, list and
 * quote markers muted, inline bold/italic/strike/code styled, `---` struck through as a
 * rule. Characters are never changed (OffsetMapping.Identity), so the caret, the IME and
 * the text the app saves are untouched.
 *
 * Styling does not depend on the caret position. Only lines whose text changed are
 * re-parsed, and each one costs a single-line parse in the core.
 */
class MarkdownVisualTransformation(
    private val baseSizeSp: Float,
    private val onSurface: Color,
    private val muted: Color,
    private val accent: Color,
    private val codeBackground: Color,
) : VisualTransformation {

    private data class CachedLine(val text: String, val styled: AnnotatedString)

    private val cache = HashMap<Int, CachedLine>()

    override fun filter(text: AnnotatedString): TransformedText {
        val lines = text.text.split('\n')
        val next = HashMap<Int, CachedLine>(lines.size)
        val builder = buildAnnotatedString {
            lines.forEachIndexed { index, line ->
                val cached = cache[index]
                val styled = if (cached != null && cached.text == line) {
                    cached.styled
                } else {
                    styleLine(line)
                }
                next[index] = CachedLine(line, styled)
                append(styled)
                if (index != lines.lastIndex) append("\n")
            }
        }
        cache.clear()
        cache.putAll(next)
        return TransformedText(builder, OffsetMapping.Identity)
    }

    private fun styleLine(line: String): AnnotatedString {
        val block = runCatching { lineBlock(line) }.getOrNull()
        val base = SpanStyle(
            fontSize = baseSizeSp.sp,
            color = onSurface,
        )

        return buildAnnotatedString {
            append(line)
            if (line.isEmpty()) return@buildAnnotatedString
            addStyle(base, 0, line.length)

            var fontSize = baseSizeSp
            var bold = false
            var markerLength = 0

            when (block) {
                is uniffi.zree_core.Block.Heading -> {
                    fontSize = baseSizeSp * when (block.level.toInt()) {
                        1 -> 1.6f
                        2 -> 1.4f
                        3 -> 1.22f
                        else -> 1.1f
                    }
                    bold = true
                    markerLength = block.level.toInt() + 1
                }
                is uniffi.zree_core.Block.ListItem -> markerLength = listMarkerLength(line)
                is uniffi.zree_core.Block.Quote -> markerLength = 1
                is uniffi.zree_core.Block.Code -> {
                    addStyle(
                        SpanStyle(fontFamily = FontFamily.Monospace, color = muted),
                        0,
                        line.length,
                    )
                }
                is uniffi.zree_core.Block.Rule -> {
                    // a rule: the dashes themselves are hidden, the line is drawn through
                    addStyle(
                        SpanStyle(
                            color = Color.Transparent,
                            textDecoration = TextDecoration.LineThrough,
                        ),
                        0,
                        line.length,
                    )
                    return@buildAnnotatedString
                }
                else -> Unit
            }

            if (bold || fontSize != baseSizeSp) {
                addStyle(
                    SpanStyle(
                        fontSize = fontSize.sp,
                        fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal,
                        color = onSurface,
                    ),
                    0,
                    line.length,
                )
            }
            if (markerLength > 0) {
                addStyle(
                    SpanStyle(color = muted),
                    0,
                    markerLength.coerceAtMost(line.length),
                )
            }

            // inline styling, positioned by the core (byte offsets → UTF-16)
            runCatching { inlineSpans(line) }.getOrNull()?.forEach { span ->
                val start = utf16Index(line, span.start.toInt())
                val end = utf16Index(line, span.end.toInt())
                if (end <= start) return@forEach
                val style = when (span.kind) {
                    SpanKind.BOLD -> SpanStyle(fontWeight = FontWeight.Bold)
                    SpanKind.ITALIC -> SpanStyle(fontStyle = FontStyle.Italic)
                    SpanKind.STRIKE -> SpanStyle(textDecoration = TextDecoration.LineThrough)
                    SpanKind.CODE -> SpanStyle(
                        fontFamily = FontFamily.Monospace,
                        background = codeBackground,
                    )
                }
                addStyle(style, start, end)
            }
        }
    }

    private fun listMarkerLength(line: String): Int {
        val trimmed = line.trimStart(' ')
        return when {
            trimmed.startsWith("- [ ] ") || trimmed.startsWith("- [x] ") -> 6
            Regex("^\\d+\\. ").containsMatchIn(trimmed) ->
                trimmed.takeWhile { it.isDigit() }.length + 2
            trimmed.length >= 2 && trimmed[1] == ' ' -> 2
            else -> 1
        }
    }

    /** Byte offset (as the core reports it) to a UTF-16 index. */
    private fun utf16Index(text: String, byteOffset: Int): Int {
        var bytes = 0
        var index = 0
        while (index < text.length && bytes < byteOffset) {
            val codePoint = text.codePointAt(index)
            bytes += utf8Length(codePoint)
            index += Character.charCount(codePoint)
        }
        return index
    }

    private fun utf8Length(codePoint: Int): Int = when {
        codePoint < 0x80 -> 1
        codePoint < 0x800 -> 2
        codePoint < 0x10000 -> 3
        else -> 4
    }
}

