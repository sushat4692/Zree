package im.sush.zree

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import uniffi.zree_core.Inline

/** Preview model: everything the renderer needs, already parsed off the main thread. */
sealed interface PBlock {
    data object Blank : PBlock
    data class Heading(val level: Int, val spans: List<Inline>) : PBlock
    data class Item(
        val indent: Int,
        val ordered: Boolean,
        val checked: Boolean?,
        val spans: List<Inline>,
    ) : PBlock
    data class Quote(val spans: List<Inline>) : PBlock
    data class Code(val lang: String, val text: String) : PBlock
    data class Image(val path: String?, val alt: String) : PBlock
    data class Para(val spans: List<Inline>) : PBlock
    data object Rule : PBlock
}

fun spansToAnnotated(
    spans: List<Inline>,
    linkColor: Color,
    onLink: (String) -> Unit,
): AnnotatedString = buildAnnotatedString {
    for (piece in spans) {
        when (piece) {
            is Inline.Text -> append(piece.v1)
            is Inline.Bold -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(piece.v1) }
            is Inline.Italic -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(piece.v1) }
            is Inline.Strike ->
                withStyle(SpanStyle(textDecoration = TextDecoration.LineThrough)) { append(piece.v1) }
            is Inline.Code ->
                withStyle(SpanStyle(fontFamily = FontFamily.Monospace)) { append(piece.v1) }
            is Inline.Link -> withLink(
                LinkAnnotation.Clickable(
                    tag = "zree",
                    styles = TextLinkStyles(
                        style = SpanStyle(
                            color = linkColor,
                            textDecoration = TextDecoration.Underline,
                        )
                    ),
                ) { onLink(piece.url) }
            ) { append(piece.text) }
            is Inline.Image -> append(piece.alt.ifEmpty { "[画像]" })
        }
    }
}

@Composable
fun PreviewList(
    blocks: List<PBlock>,
    bitmaps: Map<String, Bitmap>,
    onLink: (String) -> Unit,
) {
    val linkColor = MaterialTheme.colorScheme.primary
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 18.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        itemsIndexed(blocks) { _, block ->
            when (block) {
                is PBlock.Blank -> Spacer(Modifier.height(9.dp))

                is PBlock.Heading -> Text(
                    text = spansToAnnotated(block.spans, linkColor, onLink),
                    fontSize = when (block.level) {
                        1 -> 25.sp
                        2 -> 21.sp
                        3 -> 18.sp
                        4 -> 16.sp
                        else -> 15.sp
                    },
                    lineHeight = when (block.level) {
                        1 -> 31.sp
                        2 -> 27.sp
                        else -> 23.sp
                    },
                    fontWeight = if (block.level <= 2) FontWeight.Bold else FontWeight.SemiBold,
                    modifier = Modifier.padding(
                        top = when (block.level) {
                            1 -> 18.dp
                            2 -> 13.dp
                            else -> 9.dp
                        },
                        bottom = if (block.level <= 2) 4.dp else 2.dp,
                    ),
                )

                is PBlock.Item -> Row(
                    modifier = Modifier
                        .padding(start = (block.indent * 18).dp)
                        .padding(top = 1.dp),
                ) {
                    Text(
                        text = when {
                            block.checked != null -> if (block.checked) "✓" else "☐"
                            block.ordered -> "•"
                            else -> "–"
                        },
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.width(20.dp),
                    )
                    Text(
                        text = spansToAnnotated(block.spans, linkColor, onLink),
                        textDecoration = if (block.checked == true) TextDecoration.LineThrough else null,
                        color = if (block.checked == true) MaterialTheme.colorScheme.onSurfaceVariant
                        else MaterialTheme.colorScheme.onSurface,
                    )
                }

                is PBlock.Quote -> Row(
                    modifier = Modifier.padding(vertical = 3.dp),
                ) {
                    Box(
                        Modifier
                            .width(3.dp)
                            .heightIn(min = 18.dp)
                            .background(MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(2.dp))
                    )
                    Text(
                        text = spansToAnnotated(block.spans, linkColor, onLink),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        lineHeight = 23.sp,
                        modifier = Modifier.padding(start = 10.dp),
                    )
                }

                is PBlock.Code -> Box(
                    Modifier
                        .fillMaxWidth()
                        .padding(vertical = 5.dp)
                        .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(7.dp))
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 10.dp, vertical = 8.dp)
                ) {
                    Text(
                        block.text,
                        fontFamily = FontFamily.Monospace,
                        fontSize = 13.sp,
                    )
                }

                is PBlock.Image -> {
                    val bitmap = block.path?.let { bitmaps[it] }
                    if (bitmap != null) {
                        Image(
                            bitmap = bitmap.asImageBitmap(),
                            contentDescription = block.alt,
                            contentScale = ContentScale.Fit,
                            modifier = Modifier
                                .fillMaxWidth()
                                .heightIn(max = 320.dp),
                        )
                    } else {
                        Text(
                            "[画像が見つかりません: ${block.alt.ifEmpty { "?" }}]",
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }

                is PBlock.Rule -> HorizontalDivider(
                    modifier = Modifier.padding(vertical = 12.dp),
                    color = MaterialTheme.colorScheme.outlineVariant,
                )

                is PBlock.Para -> Text(
                    text = spansToAnnotated(block.spans, linkColor, onLink),
                    lineHeight = 23.sp,
                    modifier = Modifier.padding(top = 1.dp),
                )
            }
            HorizontalDivider(color = Color.Transparent)
        }
    }
}
