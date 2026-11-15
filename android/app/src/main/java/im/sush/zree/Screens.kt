package im.sush.zree

import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import uniffi.zree_core.CompletionKind
import uniffi.zree_core.ListAction
import uniffi.zree_core.completionContext
import uniffi.zree_core.indentLine
import uniffi.zree_core.listAction
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Switch
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import uniffi.zree_core.ConflictChoice
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
        state.error?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }
        state.vaultPath?.let {
            Text("Vault: $it", style = MaterialTheme.typography.bodySmall)
        }
    }
}

// ---------------------------------------------------------------- list

@Composable
fun ListScreen(vm: ZreeViewModel, state: UiState) {
    var showSettings by remember { mutableStateOf(false) }

    val importLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocumentTree()
    ) { uri: Uri? -> uri?.let(vm::importFromTree) }

    val exportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocumentTree()
    ) { uri: Uri? -> uri?.let(vm::exportToTree) }

    if (showSettings) {
        AutoSyncDialog(
            vm = vm,
            state = state,
            onImport = { showSettings = false; importLauncher.launch(null) },
            onExport = { showSettings = false; exportLauncher.launch(null) },
            onDismiss = { showSettings = false },
        )
    }

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
            TextButton(onClick = { showSettings = true }) { Text("⋯") }
        }

        val autoLabel = if (state.autoSync) {
            val last = if (state.lastSyncAt > 0) {
                java.text.SimpleDateFormat("HH:mm", java.util.Locale.US).format(java.util.Date(state.lastSyncAt))
            } else "—"
            "自動 ${state.autoSyncMinutes}分 · 最終 $last"
        } else {
            "自動同期オフ"
        }
        Text(
            buildString {
                state.git?.let { git ->
                    append(git.branch)
                    if (git.ahead != 0u) append("  ↑${git.ahead}")
                    if (git.behind != 0u) append("  ↓${git.behind}")
                    if (git.changed != 0u) append("  ●${git.changed}")
                    if (git.conflicts.isNotEmpty()) append("  ⚠${git.conflicts.size}")
                    append("   ")
                }
                append(autoLabel)
            },
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp),
        )

        if (state.conflicts.isNotEmpty() || state.merging) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.errorContainer)
                    .clickable { vm.openConflicts() }
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    if (state.conflicts.isEmpty()) "マージを確定してください"
                    else "衝突 ${state.conflicts.size} 件 — タップして解決",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                )
                Spacer(Modifier.weight(1f))
                Text("解決 ›", style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onErrorContainer)
            }
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
            MarkdownField(vm, state)
        }
    }
}

@Composable
private fun AutoSyncDialog(
    vm: ZreeViewModel,
    state: UiState,
    onImport: () -> Unit,
    onExport: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("自動同期") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("commit → pull → push を定期実行", modifier = Modifier.weight(1f))
                    Switch(
                        checked = state.autoSync,
                        onCheckedChange = { vm.setAutoSync(it, state.autoSyncMinutes) },
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf(1, 5, 10, 15).forEach { minutes ->
                        val on = state.autoSyncMinutes == minutes
                        Text(
                            "${minutes}分",
                            style = MaterialTheme.typography.labelMedium,
                            color = if (on) MaterialTheme.colorScheme.onPrimary
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier
                                .background(
                                    if (on) MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.surfaceVariant,
                                    RoundedCornerShape(50),
                                )
                                .clickable(enabled = state.autoSync) {
                                    vm.setAutoSync(true, minutes)
                                }
                                .padding(horizontal = 12.dp, vertical = 6.dp),
                        )
                    }
                }
                Text(
                    "変更があるときだけコミットします。衝突を検出したら停止します。" +
                        "アプリを閉じる（バックグラウンドへ）際にも1回同期します。",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                HorizontalDivider()
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = onImport) { Text("取り込み…") }
                    OutlinedButton(onClick = onExport) { Text("書き出し…") }
                }
                Text(
                    "取り込み: 選んだフォルダのMarkdownをこのVaultへコピーします（既存は上書きしません）。" +
                        "書き出し: Vaultの内容を選んだフォルダへコピーします。",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { vm.sync(); onDismiss() }) { Text("今すぐ同期") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("閉じる") } },
    )
}

// ---------------------------------------------------------------- conflicts

@Composable
fun ConflictsScreen(vm: ZreeViewModel, state: UiState) {
    BackHandler { vm.closeConflicts() }

    Column(Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = vm::closeConflicts) { Text("← 一覧") }
            Text(
                "衝突 ${state.conflicts.size} 件",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(start = 4.dp),
            )
        }
        HorizontalDivider()

        Text(
            "同じノートが複数の端末で変更されました。残す内容を選んでください。",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )

        if (state.conflicts.isNotEmpty()) {
            Row(
                modifier = Modifier.padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedButton(onClick = { vm.resolveAll(ConflictChoice.MINE) }) { Text("全て自分") }
                OutlinedButton(onClick = { vm.resolveAll(ConflictChoice.THEIRS) }) { Text("全て相手") }
            }
        }

        LazyColumn(Modifier.weight(1f)) {
            items(state.conflicts, key = { it }) { path ->
                Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
                    Text(
                        path,
                        style = MaterialTheme.typography.bodyMedium,
                        fontFamily = FontFamily.Monospace,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TextButton(onClick = { vm.resolveConflict(path, ConflictChoice.MINE) }) { Text("自分") }
                        TextButton(onClick = { vm.resolveConflict(path, ConflictChoice.THEIRS) }) { Text("相手") }
                        TextButton(onClick = { vm.resolveConflict(path, ConflictChoice.BOTH) }) { Text("両方") }
                    }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.surfaceVariant)
            }
        }

        if (state.conflicts.isEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "解決済み。コミットしてpushします。",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.weight(1f))
                Button(onClick = vm::finishMerge, enabled = !state.busy) { Text("マージ確定") }
            }
        }
    }
}

/**
 * The editor itself: a plain text field, so the platform IME handles Japanese
 * input exactly as it does in any other Android app, plus the two assists whose
 * decisions live in the Rust core (list continuation, tag completion).
 */
@Composable
private fun MarkdownField(vm: ZreeViewModel, state: UiState) {
    var value by remember(state.selectedId) {
        mutableStateOf(TextFieldValue(state.draft, TextRange(state.draft.length)))
    }
    var suggestions by remember { mutableStateOf<List<String>>(emptyList()) }

    fun updateSuggestions(text: String, cursor: Int) {
        val before = text.substring(0, cursor.coerceIn(0, text.length))
        val ctx = runCatching { completionContext(before) }.getOrNull()
        val list = when {
            ctx == null -> emptyList()
            ctx.kind == CompletionKind.TAG -> vm.suggestTags(ctx.prefix)
            else -> emptyList()
        }
        suggestions = list
    }

    fun applySuggestion(tag: String) {
        val cursor = value.selection.start.coerceIn(0, value.text.length)
        val before = value.text.substring(0, cursor)
        val ctx = runCatching { completionContext(before) }.getOrNull() ?: return
        val start = cursor - ctx.prefix.length
        val newText = value.text.substring(0, start) + tag + value.text.substring(cursor)
        val next = TextFieldValue(newText, TextRange(start + tag.length))
        value = next
        vm.setDraft(newText)
        suggestions = emptyList()
    }

    LaunchedEffect(state.selectedId) {
        // keep the field in sync when the note changes underneath us
        if (value.text != state.draft) {
            value = TextFieldValue(state.draft, TextRange(state.draft.length))
        }
    }

    fun lineRange(text: String, caret: Int): IntRange {
        val start = if (caret == 0) 0 else text.lastIndexOf('\n', caret - 1).let { if (it < 0) 0 else it + 1 }
        val end = text.indexOf('\n', caret).let { if (it < 0) text.length else it }
        return start..end
    }

    fun applyIndent(outdent: Boolean) {
        val caret = value.selection.start.coerceIn(0, value.text.length)
        val range = lineRange(value.text, caret)
        val line = value.text.substring(range.first, range.last)
        val rewritten = runCatching { indentLine(line, outdent) }.getOrNull() ?: return
        val text = value.text.substring(0, range.first) + rewritten + value.text.substring(range.last)
        val delta = rewritten.length - line.length
        val target = (caret + delta).coerceIn(range.first, range.first + rewritten.length)
        value = TextFieldValue(text, TextRange(target))
        vm.setDraft(text)
    }

    fun applyLinePrefix(prefix: String) {
        val caret = value.selection.start.coerceIn(0, value.text.length)
        val range = lineRange(value.text, caret)
        val line = value.text.substring(range.first, range.last)
        if (line.startsWith(prefix)) return
        val stripped = line.trimStart(' ')
        val text = value.text.substring(0, range.first) + prefix + stripped + value.text.substring(range.last)
        value = TextFieldValue(text, TextRange(range.first + prefix.length + stripped.length))
        vm.setDraft(text)
    }

    fun wrap(marks: String) {
        val sel = value.selection
        val text = value.text
        val start = minOf(sel.start, sel.end).coerceIn(0, text.length)
        val end = maxOf(sel.start, sel.end).coerceIn(0, text.length)
        val selected = text.substring(start, end)
        val newText = text.substring(0, start) + marks + selected + marks + text.substring(end)
        val caret = start + marks.length + selected.length
        value = TextFieldValue(newText, TextRange(caret))
        vm.setDraft(newText)
    }

    Column(Modifier.fillMaxSize()) {
        EditorToolbar(
            onOutdent = { applyIndent(true) },
            onIndent = { applyIndent(false) },
            onBullet = { applyLinePrefix("- ") },
            onCheckbox = { applyLinePrefix("- [ ] ") },
            onHeading = { applyLinePrefix("# ") },
            onBold = { wrap("**") },
        )

        if (suggestions.isNotEmpty()) {
            LazyRow(
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                items(suggestions, key = { it }) { tag ->
                    Text(
                        "#$tag",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onPrimary,
                        modifier = Modifier
                            .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(50))
                            .clickable { applySuggestion(tag) }
                            .padding(horizontal = 10.dp, vertical = 5.dp),
                    )
                }
            }
        }

        BasicTextField(
            value = value,
            onValueChange = { next ->
                val assisted = applyEditorAssists(value, next)
                value = assisted
                vm.setDraft(assisted.text)
                updateSuggestions(assisted.text, assisted.selection.start)
            },
            textStyle = TextStyle(
                fontSize = 15.sp,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurface,
            ),
            cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Default, keyboardType = KeyboardType.Text),
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp)
                .onPreviewKeyEvent { event ->
                    // hardware keyboards: Tab indents, Shift-Tab outdents
                    if (event.type == KeyEventType.KeyDown && event.key == Key.Tab) {
                        applyIndent(event.isShiftPressed)
                        true
                    } else {
                        false
                    }
                },
        )
    }
}

@Composable
private fun EditorToolbar(
    onOutdent: () -> Unit,
    onIndent: () -> Unit,
    onBullet: () -> Unit,
    onCheckbox: () -> Unit,
    onHeading: () -> Unit,
    onBold: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        listOf(
            "⇤" to onOutdent,
            "⇥" to onIndent,
            "•" to onBullet,
            "☐" to onCheckbox,
            "H" to onHeading,
            "B" to onBold,
        ).forEach { (label, action) ->
            Text(
                label,
                style = MaterialTheme.typography.titleSmall,
                fontFamily = FontFamily.Monospace,
                modifier = Modifier
                    .clickable(onClick = action)
                    .padding(horizontal = 14.dp, vertical = 10.dp),
            )
        }
    }
}

/**
 * Return-key list continuation, decided by the core.
 *
 * Works for a newline inserted anywhere, not just at the end of the document:
 * true for a caret in the middle of a note, which is the common case.
 */
private fun applyEditorAssists(old: TextFieldValue, next: TextFieldValue): TextFieldValue {
    val caret = old.selection.start.coerceIn(0, old.text.length)
    val insertedNewline = next.text.length == old.text.length + 1 &&
        next.text == old.text.substring(0, caret) + "\n" + old.text.substring(caret)
    if (!insertedNewline) return next

    val lineStart = old.text.lastIndexOf('\n', startIndex = (caret - 1).coerceAtLeast(0))
        .let { if (it < 0) 0 else it + 1 }
    // careful: lastIndexOf with startIndex 0 still matches at 0 only when the char is there
    val start = if (caret == 0) 0 else lineStart
    val line = old.text.substring(start, caret)

    val action = runCatching { listAction(line) }.getOrNull() ?: return next

    return when (action) {
        is ListAction.Continue -> {
            val marker = action.marker
            val text = old.text.substring(0, caret) + "\n" + marker + old.text.substring(caret)
            TextFieldValue(text, TextRange(caret + 1 + marker.length))
        }
        is ListAction.Replace -> {
            // empty item: outdent one level, or drop the marker at the left margin
            val text = old.text.substring(0, start) + action.marker + old.text.substring(caret)
            TextFieldValue(text, TextRange(start + action.marker.length))
        }
        else -> next
    }
}
