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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
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
import uniffi.zree_core.BlockKind
import uniffi.zree_core.completionContext
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
import androidx.compose.runtime.key
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
            "ノートはプレーンなMarkdownです。Gitリポジトリを複製するか、空のツリーから始めます。",
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
                Text("空のツリーを作る")
            }
        }

        if (state.recentTrees.isNotEmpty()) {
            HorizontalDivider()
            Text("最近のツリー", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            state.recentTrees.forEach { path ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { vm.openVault(path) }
                        .padding(vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(path.substringAfterLast('/'), style = MaterialTheme.typography.bodyMedium)
                        Text(path, style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.MiddleEllipsis)
                    }
                    TextButton(onClick = { vm.forgetTree(path) }) { Text("外す") }
                }
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
            Text("ツリー: $it", style = MaterialTheme.typography.bodySmall)
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

    Column(Modifier.fillMaxSize().imePadding()) {
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
                    OutlinedButton(onClick = { vm.showSetup(); onDismiss() }) { Text("ツリーを切り替え…") }
                    OutlinedButton(onClick = onImport) { Text("取り込み…") }
                    OutlinedButton(onClick = onExport) { Text("書き出し…") }
                }
                Text(
                    "取り込み: 選んだフォルダのMarkdownをこのツリーへコピーします（既存は上書きしません）。" +
                        "書き出し: ツリーの内容を選んだフォルダへコピーします。",
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

    fun current(): EditText = EditText(value.text, value.selection.start, value.selection.end)

    fun apply(edit: EditText) {
        if (edit.text == value.text && edit.selStart == value.selection.start && edit.selEnd == value.selection.end) return
        value = TextFieldValue(edit.text, TextRange(edit.selStart, edit.selEnd))
        vm.setDraft(edit.text)
    }

    fun updateSuggestions(text: String, cursor: Int) {
        val before = text.substring(0, cursor.coerceIn(0, text.length))
        val ctx = runCatching { completionContext(before) }.getOrNull()
        suggestions = when {
            ctx == null -> emptyList()
            ctx.kind == CompletionKind.TAG -> vm.suggestTags(ctx.prefix)
            else -> emptyList()
        }
    }

    fun applySuggestion(tag: String) {
        val cursor = value.selection.start.coerceIn(0, value.text.length)
        val before = value.text.substring(0, cursor)
        val ctx = runCatching { completionContext(before) }.getOrNull() ?: return
        val start = cursor - ctx.prefix.length
        val newText = value.text.substring(0, start) + tag + value.text.substring(cursor)
        apply(EditText(newText, start + tag.length, start + tag.length))
        suggestions = emptyList()
    }

    LaunchedEffect(state.selectedId) {
        if (value.text != state.draft) {
            value = TextFieldValue(state.draft, TextRange(state.draft.length))
        }
    }

    Column(Modifier.fillMaxSize()) {
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

        // keyed on the note so the field — and its undo history — start fresh;
        // otherwise undo after switching could pull the previous note's text in
        key(state.selectedId) {
            BasicTextField(
                value = value,
                onValueChange = { next ->
                    val old = current()
                    val assisted = EditorEdits.newline(
                        old,
                        EditText(next.text, next.selection.start, next.selection.end),
                    )
                    if (assisted != null) {
                        value = TextFieldValue(assisted.text, TextRange(assisted.selStart, assisted.selEnd))
                        vm.setDraft(assisted.text)
                        updateSuggestions(assisted.text, assisted.selStart)
                    } else {
                        value = next
                        vm.setDraft(next.text)
                        updateSuggestions(next.text, next.selection.start)
                    }
                },
                textStyle = TextStyle(
                    fontSize = 15.sp,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurface,
                ),
                cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Default, keyboardType = KeyboardType.Text),
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(16.dp)
                    .onPreviewKeyEvent { event ->
                        if (event.type == KeyEventType.KeyDown && event.key == Key.Tab) {
                            apply(EditorEdits.indent(current(), outdent = event.isShiftPressed))
                            true
                        } else {
                            false
                        }
                    },
            )
        }

        // Sits directly above the keyboard (an input accessory bar).
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        EditorToolbar(
            onOutdent = { apply(EditorEdits.indent(current(), outdent = true)) },
            onIndent = { apply(EditorEdits.indent(current(), outdent = false)) },
            onBullet = { apply(EditorEdits.block(current(), BlockKind.BULLET)) },
            onOrdered = { apply(EditorEdits.block(current(), BlockKind.ORDERED)) },
            onTask = { apply(EditorEdits.block(current(), BlockKind.TASK)) },
            onHeading = { apply(EditorEdits.block(current(), BlockKind.HEADING)) },
            onQuote = { apply(EditorEdits.block(current(), BlockKind.QUOTE)) },
            onToggleTask = { apply(EditorEdits.taskToggle(current())) },
            onBold = { apply(EditorEdits.toggleInline(current(), "**")) },
        )
    }
}

@Composable
private fun EditorToolbar(
    onOutdent: () -> Unit,
    onIndent: () -> Unit,
    onBullet: () -> Unit,
    onOrdered: () -> Unit,
    onTask: () -> Unit,
    onHeading: () -> Unit,
    onQuote: () -> Unit,
    onToggleTask: () -> Unit,
    onBold: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 8.dp)
            .navigationBarsPadding(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        listOf(
            "⇤" to onOutdent,
            "⇥" to onIndent,
            "•" to onBullet,
            "1." to onOrdered,
            "☐" to onTask,
            "☑" to onToggleTask,
            "H" to onHeading,
            "❝" to onQuote,
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

