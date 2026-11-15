package im.sush.zree

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import uniffi.zree_core.TagCount

// ---------------------------------------------------------------- setup

@Composable
fun SetupScreen(vm: ZreeViewModel, state: UiState) {
    var url by remember { mutableStateOf("") }
    var pat by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Zree", style = MaterialTheme.typography.headlineMedium)
        Text(
            "ノートはプレーンなMarkdownです。Gitリポジトリを複製するか、空のVaultから始めます。",
            style = MaterialTheme.typography.bodyMedium,
        )
        Spacer(Modifier.height(4.dp))

        OutlinedTextField(
            value = url,
            onValueChange = { url = it },
            label = { Text("リモートURL") },
            placeholder = { Text("https://github.com/you/vault.git") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Next),
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = pat,
            onValueChange = { pat = it },
            label = { Text("Personal Access Token（プライベートの場合）") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
            modifier = Modifier.fillMaxWidth(),
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                onClick = { vm.cloneFromGit(url, pat) },
                enabled = !state.busy && (url.contains("/") || url.contains(":")),
            ) { Text("クローンして開く") }
            OutlinedButton(onClick = { vm.createEmptyVault() }, enabled = !state.busy) {
                Text("空のVaultを作る")
            }
        }

        if (state.busy) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.width(18.dp).height(18.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(8.dp))
                Text(state.message ?: "処理中…", style = MaterialTheme.typography.bodySmall)
            }
        }
        state.vaultPath?.let {
            Text("Vault: $it", style = MaterialTheme.typography.bodySmall)
        }
    }
}

// ---------------------------------------------------------------- list

@Composable
fun ListScreen(vm: ZreeViewModel, state: UiState) {
    Column(Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BasicTextField(
                value = state.query,
                onValueChange = vm::setQuery,
                singleLine = true,
                textStyle = TextStyle(
                    fontSize = 16.sp,
                    color = MaterialTheme.colorScheme.onSurface,
                ),
                cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                modifier = Modifier
                    .weight(1f)
                    .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(8.dp))
                    .padding(horizontal = 12.dp, vertical = 10.dp),
                decorationBox = { inner ->
                    if (state.query.isEmpty()) {
                        Text("検索（日本語OK）", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    inner()
                },
            )
            Spacer(Modifier.width(8.dp))
            TextButton(onClick = vm::sync, enabled = !state.busy) { Text("同期") }
        }

        state.git?.let { git ->
            Text(
                buildString {
                    append(git.branch)
                    if (git.ahead != 0u) append("  ↑${git.ahead}")
                    if (git.behind != 0u) append("  ↓${git.behind}")
                    if (git.changed != 0u) append("  ●${git.changed}")
                    if (git.conflicts.isNotEmpty()) append("  ⚠${git.conflicts.size}")
                },
                style = MaterialTheme.typography.labelSmall,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
        }

        TagStrip(state.tags, state.activeTags, vm::toggleTag)
        HorizontalDivider()

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "${state.rows.size} / ${state.allCount} ノート",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.weight(1f))
            TextButton(onClick = vm::newNote) { Text("新規") }
        }

        LazyColumn(Modifier.fillMaxSize()) {
            items(state.rows, key = { it.id }) { row ->
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clickable { vm.openNote(row.id) }
                        .padding(horizontal = 16.dp, vertical = 10.dp)
                ) {
                    Text(row.title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                    if (row.snippet.isNotEmpty()) {
                        Text(
                            row.snippet,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 2,
                        )
                    }
                    if (row.tags.isNotEmpty()) {
                        Text(
                            row.tags.take(3).joinToString(" ") { "#$it" },
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.surfaceVariant)
            }
        }
    }
}

@Composable
private fun TagStrip(tags: List<TagCount>, active: Set<String>, onToggle: (String) -> Unit) {
    if (tags.isEmpty()) return
    LazyRow(
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 12.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        items(tags.take(40), key = { it.tag }) { tag ->
            val on = tag.tag in active
            Box(
                Modifier
                    .background(
                        if (on) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.surfaceVariant,
                        RoundedCornerShape(50),
                    )
                    .clickable { onToggle(tag.tag) }
                    .padding(horizontal = 10.dp, vertical = 5.dp)
            ) {
                Text(
                    "#${tag.tag} ${tag.count}",
                    style = MaterialTheme.typography.labelSmall,
                    color = if (on) MaterialTheme.colorScheme.onPrimary
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ---------------------------------------------------------------- editor

@Composable
fun EditorScreen(vm: ZreeViewModel, state: UiState) {
    var title by remember(state.selectedId) { mutableStateOf(state.title) }

    // Back returns to the list (and saves); closing the app is not what a back
    // press inside the editor should do.
    BackHandler(enabled = true) { vm.backToList() }

    Column(Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = vm::backToList) { Text("← 一覧") }
            BasicTextField(
                value = title,
                onValueChange = { title = it },
                singleLine = true,
                textStyle = TextStyle(
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                ),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 4.dp)
                    // rename when the field loses focus (no explicit button)
                    .onFocusChanged { focus ->
                        if (!focus.isFocused) vm.rename(title)
                    },
            )
            TextButton(onClick = vm::togglePreview) {
                Text(if (state.preview) "編集" else "プレビュー")
            }
        }
        HorizontalDivider()

        if (state.preview) {
            PreviewList(
                blocks = state.pblocks,
                bitmaps = state.bitmaps,
                onLink = vm::openLink,
            )
        } else {
            // The editor itself: a plain text field, so the platform IME handles
            // Japanese input exactly as it does in any other Android app.
            BasicTextField(
                value = state.draft,
                onValueChange = vm::setDraft,
                textStyle = TextStyle(
                    fontSize = 15.sp,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurface,
                ),
                cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Default, keyboardType = KeyboardType.Text),
                modifier = Modifier
                    .fillMaxSize()
                    .padding(16.dp),
            )
        }
    }
}
