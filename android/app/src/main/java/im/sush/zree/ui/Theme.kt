package im.sush.zree.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Palette sampled from the app icon (tree #559955, trunk #112233,
// background gradient #FAFAF6 -> #DCEBE0).
object ZreeColors {
    val Leaf = Color(0xFF3C7D57)
    val LeafLight = Color(0xFF8FCBA4)
    val Mint = Color(0xFFDCEBE0)
    val MintDark = Color(0xFF2C4A38)
    val Paper = Color(0xFFFAFAF6)
    val Ink = Color(0xFF1A2620)
    val Trunk = Color(0xFF22323F)
    val Outline = Color(0xFF96A79A)
}

private val LightScheme = lightColorScheme(
    primary = ZreeColors.Leaf,
    onPrimary = Color.White,
    primaryContainer = ZreeColors.Mint,
    onPrimaryContainer = Color(0xFF10241A),
    secondary = Color(0xFF55705F),
    onSecondary = Color.White,
    secondaryContainer = ZreeColors.Mint,
    onSecondaryContainer = Color(0xFF10241A),
    tertiary = ZreeColors.Trunk,
    background = ZreeColors.Paper,
    onBackground = ZreeColors.Ink,
    surface = ZreeColors.Paper,
    onSurface = ZreeColors.Ink,
    surfaceVariant = Color(0xFFE3EDE5),
    onSurfaceVariant = Color(0xFF46564C),
    outline = ZreeColors.Outline,
    outlineVariant = Color(0xFFC8D8CC),
    errorContainer = Color(0xFFF7DDD8),
    onErrorContainer = Color(0xFF3B1912),
)

private val DarkScheme = darkColorScheme(
    primary = ZreeColors.LeafLight,
    onPrimary = Color(0xFF0A2317),
    primaryContainer = ZreeColors.MintDark,
    onPrimaryContainer = Color(0xFFC8E6D3),
    secondary = Color(0xFFA6C4B1),
    onSecondary = Color(0xFF0A2317),
    secondaryContainer = Color(0xFF37493E),
    onSecondaryContainer = Color(0xFFC8E6D3),
    tertiary = Color(0xFFA9C0D6),
    background = Color(0xFF121A16),
    onBackground = Color(0xFFE4EDE6),
    surface = Color(0xFF121A16),
    onSurface = Color(0xFFE4EDE6),
    surfaceVariant = Color(0xFF2A3630),
    onSurfaceVariant = Color(0xFFB9C9BD),
    outline = Color(0xFF5C6F62),
    outlineVariant = Color(0xFF3A4A40),
    errorContainer = Color(0xFF4E2A24),
    onErrorContainer = Color(0xFFFFD9D1),
)

@Composable
fun ZreeTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkScheme else LightScheme,
        content = content,
    )
}
