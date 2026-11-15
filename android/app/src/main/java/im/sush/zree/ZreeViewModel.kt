package im.sush.zree

import android.app.Application
import android.content.Context
import android.net.Uri
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.documentfile.provider.DocumentFile
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.zree_core.Block
import uniffi.zree_core.ConflictChoice
import uniffi.zree_core.GitRepo
import uniffi.zree_core.GitStatus
import uniffi.zree_core.NoteMeta
import uniffi.zree_core.TagCount
import uniffi.zree_core.ZreeSession
import uniffi.zree_core.isGitRepo
import uniffi.zree_core.setGitCaBundle
import java.io.File

data class Row(
    val id: String,
    val title: String,
    val snippet: String,
    val tags: List<String>,
    val mtimeMs: Long,
)

enum class Screen { Setup, List, Editor, Conflicts }

data class UiState(
    val screen: Screen = Screen.Setup,
    val vaultPath: String? = null,
    val rows: List<Row> = emptyList(),
    val allCount: Int = 0,
    val tags: List<TagCount> = emptyList(),
    val query: String = "",
    val activeTags: Set<String> = emptySet(),
    val selectedId: String? = null,
    val title: String = "",
    val draft: String = "",
    val preview: Boolean = false,
    val pblocks: List<PBlock> = emptyList(),
    val bitmaps: Map<String, Bitmap> = emptyMap(),
    val git: GitStatus? = null,
    val busy: Boolean = false,
    val autoSync: Boolean = true,
    val autoSyncMinutes: Int = 5,
    val lastSyncAt: Long = 0L,
    val conflicts: List<String> = emptyList(),
    val merging: Boolean = false,
    val message: String? = null,
    val error: String? = null,
)

class ZreeViewModel(app: Application) : AndroidViewModel(app) {
    private val prefs = app.getSharedPreferences("zree", Context.MODE_PRIVATE)
    private val tokens = TokenStore(app)

    private var session: ZreeSession? = null
    private var repo: GitRepo? = null
    private var seenMtime = 0L
    private var saveJob: Job? = null
    private var previewJob: Job? = null
    private var autoSyncJob: Job? = null
    private var consecutiveFailures = 0
    private var dirty = false

    private val _state = MutableStateFlow(UiState())
    val state = _state.asStateFlow()

    init {
        // must happen before any TLS call
        CaBundle.ensure(app)?.let { path ->
            runCatching { setGitCaBundle(path) }
                .onSuccess { Log.i("Zree", "CA bundle installed: $path") }
                .onFailure { Log.e("Zree", "CA bundle rejected: $path", it) }
        }
        _state.value = _state.value.copy(
            autoSync = prefs.getBoolean(KEY_AUTO_ON, true),
            autoSyncMinutes = prefs.getInt(KEY_AUTO_MIN, 5).coerceIn(1, 60),
            lastSyncAt = prefs.getLong(KEY_LAST_SYNC, 0L),
        )
        prefs.getString(KEY_VAULT, null)?.let { path ->
            if (File(path).isDirectory) openVault(path)
        }
    }

    // MARK: - setup

    val defaultVaultPath: String
        get() = File(getApplication<Application>().filesDir, "vault").absolutePath

    fun cloneFromGit(url: String, pat: String) = io {
        _state.value = _state.value.copy(busy = true, error = null, message = "クローン中…")
        val target = File(defaultVaultPath)
        if (target.exists() && target.listFiles()?.isNotEmpty() == true) {
            throw IllegalStateException("保存先に既にファイルがあります: ${target.absolutePath}")
        }
        target.mkdirs()
        if (pat.isNotBlank()) tokens.save(pat)
        GitRepo.clone(url.trim(), target.absolutePath, null, pat.takeIf { it.isNotBlank() })
        openVaultInternal(target.absolutePath)
    }

    fun createEmptyVault() = io {
        val target = File(defaultVaultPath)
        target.mkdirs()
        File(target, "ようこそ.md").writeText("#ようこそ\n\nZreeへようこそ。ここに書いていきます。\n")
        openVaultInternal(target.absolutePath)
    }

    fun openVault(path: String) = io { openVaultInternal(path) }

    private suspend fun openVaultInternal(path: String) {
        session?.close()
        session = ZreeSession.open(path)
        repo = if (isGitRepo(path)) {
            GitRepo.open(path, null, tokens.get())
        } else {
            null
        }
        prefs.edit().putString(KEY_VAULT, path).apply()
        _state.value = _state.value.copy(
            vaultPath = path,
            screen = Screen.List,
            busy = false,
            message = null,
            error = null,
        )
        refresh()
        autoPullOnOpen()
        restartAutoSync()
    }

    // MARK: - listing

    fun refresh() = io {
        val s = session ?: return@io
        val rows = s.search(_state.value.query, _state.value.activeTags.toList(), 0u).map {
            Row(it.id, it.title, it.snippet, it.tags, it.mtimeMs)
        }
        val all = s.search("", emptyList(), 0u).size
        _state.value = _state.value.copy(rows = rows, allCount = all, tags = s.tags())
    }

    fun setQuery(q: String) {
        _state.value = _state.value.copy(query = q)
        refresh()
    }

    fun toggleTag(tag: String) {
        val now = _state.value.activeTags.toMutableSet()
        if (!now.add(tag)) now.remove(tag)
        _state.value = _state.value.copy(activeTags = now)
        refresh()
    }

    // MARK: - editing

    fun openNote(id: String) = io {
        save()
        openNoteInternal(id)
    }

    private suspend fun openNoteInternal(id: String) {
        val s = session ?: return
        val body = s.read(id)
        val row = _state.value.rows.firstOrNull { it.id == id }
        seenMtime = row?.mtimeMs ?: 0L
        dirty = false
        _state.value = _state.value.copy(
            screen = Screen.Editor,
            selectedId = id,
            title = row?.title ?: id.removeSuffix(".md"),
            draft = body,
            pblocks = emptyList(),
            bitmaps = emptyMap(),
        )
        if (_state.value.preview) refreshPreview()
    }

    fun togglePreview() {
        val on = !_state.value.preview
        _state.value = _state.value.copy(preview = on)
        if (on) refreshPreview()
    }

    private fun refreshPreview() = io {
        val s = session ?: return@io
        val vault = _state.value.vaultPath
        val bitmaps = HashMap<String, Bitmap>()

        val blocks = s.blocksOf(_state.value.draft).map { b ->
            when (b) {
                is Block.Blank -> PBlock.Blank
                is Block.Heading -> PBlock.Heading(b.level.toInt(), s.inline(b.text))
                is Block.ListItem ->
                    PBlock.Item(b.indent.toInt(), b.ordered, b.checked, s.inline(b.text))
                is Block.Quote -> PBlock.Quote(s.inline(b.text))
                is Block.Code -> PBlock.Code(b.lang, b.text)
                is Block.Paragraph -> PBlock.Para(s.inline(b.text))
                is Block.Image -> {
                    val path = resolveAsset(vault, b.src)
                    if (path != null && path !in bitmaps) {
                        BitmapFactory.decodeFile(path)?.let { bitmaps[path] = it }
                    }
                    PBlock.Image(path, b.alt)
                }
            }
        }
        _state.value = _state.value.copy(pblocks = blocks, bitmaps = bitmaps)
    }

    private fun resolveAsset(vault: String?, src: String): String? {
        if (vault == null || src.isBlank()) return null
        val direct = File(vault, src)
        if (direct.isFile) return direct.absolutePath
        val byName = File(vault, File(src).name)
        return if (byName.isFile) byName.absolutePath else null
    }

    /** Follow a Markdown link inside the preview. */
    fun openLink(href: String) = io {
        val s = session ?: return@io
        val from = _state.value.selectedId ?: return@io
        val target = s.resolveLink(from, href) ?: return@io
        save()
        openNoteInternal(target)
    }

    fun setDraft(text: String) {
        dirty = true
        _state.value = _state.value.copy(draft = text)
        saveJob?.cancel()
        saveJob = viewModelScope.launch {
            delay(700)
            save()
        }
        if (_state.value.preview) {
            previewJob?.cancel()
            previewJob = viewModelScope.launch {
                delay(400)
                refreshPreview()
            }
        }
    }

    fun save() = io {
        val s = session ?: return@io
        val id = _state.value.selectedId ?: return@io
        if (!dirty) return@io
        val meta = s.write(id, _state.value.draft, seenMtime)
        seenMtime = meta.mtimeMs
        dirty = false
    }

    fun rename(title: String) = io {
        val s = session ?: return@io
        val id = _state.value.selectedId ?: return@io
        val wanted = title.trim()
        if (wanted.isEmpty() || wanted == _state.value.title) return@io
        save()
        val meta = s.rename(id, wanted)
        seenMtime = meta.mtimeMs
        _state.value = _state.value.copy(selectedId = meta.id, title = meta.title)
        refresh()
    }

    fun backToList() {
        viewModelScope.launch {
            save()
            withContext(Dispatchers.IO) { refresh() }
            _state.value = _state.value.copy(
                screen = Screen.List,
                selectedId = null,
                draft = "",
                pblocks = emptyList(),
                bitmaps = emptyMap(),
            )
        }
    }

    fun newNote() = io {
        val s = session ?: return@io
        save()
        val meta = s.create(null, "")
        refresh()
        seenMtime = meta.mtimeMs
        dirty = false
        _state.value = _state.value.copy(
            screen = Screen.Editor,
            selectedId = meta.id,
            title = meta.title,
            draft = "",
        )
    }

    fun trashCurrent() = io {
        val s = session ?: return@io
        val id = _state.value.selectedId ?: return@io
        dirty = false
        s.trash(id)
        _state.value = _state.value.copy(screen = Screen.List, selectedId = null, draft = "")
        refresh()
    }

    // MARK: - git

    fun refreshGit() = io {
        _state.value = _state.value.copy(git = repo?.status())
    }

    private suspend fun autoPullOnOpen() {
        val r = repo ?: return
        val st = r.status()
        _state.value = _state.value.copy(git = st)
        if (st.changed != 0u || st.behind == 0u || st.conflicts.isNotEmpty() || st.merging) return
        runCatching { r.pull() }
        withContext(Dispatchers.IO) { refresh() }
        _state.value = _state.value.copy(git = runCatching { r.status() }.getOrNull())
    }

    fun sync() = io { runSync(auto = false) }

    private suspend fun runSync(auto: Boolean) {
        val r = repo ?: return
        save()
        if (!auto) _state.value = _state.value.copy(busy = true, message = "同期中…")
        try {
            val message = if (auto) {
                "zree: autosync ${java.text.SimpleDateFormat("MM-dd HH:mm", java.util.Locale.US).format(java.util.Date())}"
            } else {
                "zree: sync from android"
            }
            val report = r.sync(message)
            consecutiveFailures = 0
            val now = System.currentTimeMillis()
            prefs.edit().putLong(KEY_LAST_SYNC, now).apply()
            refresh()
            _state.value = _state.value.copy(
                busy = false,
                lastSyncAt = now,
                git = runCatching { r.status() }.getOrNull(),
                conflicts = report.conflicts,
                merging = runCatching { r.status() }.getOrNull()?.merging ?: false,
                message = when {
                    report.conflicts.isNotEmpty() -> "衝突 ${report.conflicts.size} 件"
                    auto -> _state.value.message
                    else -> "同期しました"
                },
                error = if (report.conflicts.isEmpty()) _state.value.error
                else "衝突を解決してください: ${report.conflicts.joinToString(", ")}",
            )
        } catch (t: Throwable) {
            consecutiveFailures += 1
            if (auto && consecutiveFailures >= 3) {
                setAutoSync(false, _state.value.autoSyncMinutes)
                _state.value = _state.value.copy(
                    busy = false,
                    message = null,
                    error = "自動同期を停止しました（3回連続で失敗）: ${t.message ?: t}",
                )
            } else {
                _state.value = _state.value.copy(
                    busy = false,
                    message = null,
                    error = t.message ?: t.toString(),
                )
            }
        }
    }

    // MARK: - auto sync

    fun setAutoSync(enabled: Boolean, minutes: Int) {
        prefs.edit()
            .putBoolean(KEY_AUTO_ON, enabled)
            .putInt(KEY_AUTO_MIN, minutes)
            .apply()
        _state.value = _state.value.copy(autoSync = enabled, autoSyncMinutes = minutes)
        restartAutoSync()
    }

    private fun restartAutoSync() {
        autoSyncJob?.cancel()
        autoSyncJob = null
        consecutiveFailures = 0
        val st = _state.value
        if (!st.autoSync || repo == null) return
        val period = st.autoSyncMinutes.coerceIn(1, 60) * 60_000L
        autoSyncJob = viewModelScope.launch(Dispatchers.IO) {
            while (isActive) {
                delay(period)
                val git = runCatching { repo?.status() }.getOrNull() ?: continue
                if (git.merging || git.conflicts.isNotEmpty()) continue
                runSync(auto = true)
            }
        }
    }

    /** Best-effort flush when the app leaves the foreground. */
    fun onAppBackground() {
        viewModelScope.launch(Dispatchers.IO) {
            save()
            if (_state.value.autoSync) runSync(auto = true)
        }
    }

    // MARK: - conflicts

    fun openConflicts() {
        _state.value = _state.value.copy(screen = Screen.Conflicts)
    }

    fun closeConflicts() {
        _state.value = _state.value.copy(screen = Screen.List)
        refresh()
    }

    fun resolveConflict(path: String, choice: ConflictChoice) = io {
        val r = repo ?: return@io
        r.resolve(path, choice)
        refreshConflicts(r)
    }

    fun resolveAll(choice: ConflictChoice) = io {
        val r = repo ?: return@io
        for (path in _state.value.conflicts) {
            runCatching { r.resolve(path, choice) }
        }
        refreshConflicts(r)
    }

    fun finishMerge() = io {
        val r = repo ?: return@io
        r.commitMerge("zree: resolve conflicts")
        runCatching { r.push() }
        refreshConflicts(r)
        refresh()
        _state.value = _state.value.copy(screen = Screen.List, message = "衝突を解決してpushしました")
    }

    private suspend fun refreshConflicts(r: GitRepo) {
        val st = r.status()
        _state.value = _state.value.copy(
            git = st,
            conflicts = st.conflicts,
            merging = st.merging,
        )
    }

    // MARK: - SAF import / export

    /** Copy every .md (and assets/) from a picked folder into the vault. */
    fun importFromTree(treeUri: Uri) = io {
        val context = getApplication<Application>()
        val root = DocumentFile.fromTreeUri(context, treeUri)
            ?: throw IllegalStateException("フォルダを開けませんでした")
        val target = File(defaultVaultPath).apply { mkdirs() }

        var copied = 0
        var skipped = 0

        fun uniqueFile(dir: File, name: String): File {
            var candidate = File(dir, name)
            var n = 2
            while (candidate.exists()) {
                val base = name.substringBeforeLast('.')
                val ext = name.substringAfterLast('.', "")
                candidate = File(dir, if (ext.isEmpty()) "$base $n" else "$base $n.$ext")
                n++
            }
            return candidate
        }

        fun copyFile(source: DocumentFile, name: String, dir: File) {
            dir.mkdirs()
            val bytes = context.contentResolver.openInputStream(source.uri)?.use { it.readBytes() }
            if (bytes == null) {
                skipped++
                return
            }
            uniqueFile(dir, name).writeBytes(bytes)
            copied++
        }

        fun walk(dir: DocumentFile, outDir: File, depth: Int) {
            if (depth > 6) return
            for (child in dir.listFiles()) {
                val name = child.name ?: continue
                if (name.startsWith(".")) continue
                when {
                    child.isDirectory && name == "assets" -> walk(child, File(target, "assets"), depth + 1)
                    child.isDirectory -> walk(child, outDir, depth + 1)
                    name.lowercase().endsWith(".md") -> copyFile(child, name, outDir)
                }
            }
        }

        walk(root, target, 0)
        refresh()
        _state.value = _state.value.copy(
            message = if (copied == 0) "取り込めるMarkdownがありませんでした"
            else "${copied}件を取り込みました" + if (skipped > 0) "（${skipped}件失敗）" else "",
        )
    }

    /** Write the whole vault (notes and assets) into a picked folder. */
    fun exportToTree(treeUri: Uri) = io {
        val context = getApplication<Application>()
        val root = DocumentFile.fromTreeUri(context, treeUri)
            ?: throw IllegalStateException("フォルダを開けませんでした")
        val vault = File(defaultVaultPath)
        var written = 0

        fun ensureDir(dir: DocumentFile, name: String): DocumentFile =
            dir.findFile(name)?.takeIf { it.isDirectory }
                ?: dir.createDirectory(name)
                ?: throw IllegalStateException("フォルダを作れません: $name")

        fun writeFile(dir: DocumentFile, name: String, bytes: ByteArray) {
            val existing = dir.findFile(name)
            val file = existing ?: dir.createFile("application/octet-stream", name)
            ?: throw IllegalStateException("ファイルを作れません: $name")
            context.contentResolver.openOutputStream(file.uri)?.use { it.write(bytes) }
            written++
        }

        fun walk(src: File, dest: DocumentFile) {
            for (f in src.listFiles().orEmpty()) {
                if (f.name.startsWith(".")) continue
                if (f.isDirectory) {
                    walk(f, ensureDir(dest, f.name))
                } else {
                    writeFile(dest, f.name, f.readBytes())
                }
            }
        }

        vault.mkdirs()
        walk(vault, root)
        _state.value = _state.value.copy(
            message = if (written == 0) "書き出すものがありません" else "${written}件を書き出しました",
        )
    }

    fun dismissMessage() {
        _state.value = _state.value.copy(message = null, error = null)
    }

    // MARK: - plumbing

    private fun io(block: suspend () -> Unit) {
        viewModelScope.launch(Dispatchers.IO) {
            runCatching { block() }.onFailure { t ->
                Log.e(TAG, "operation failed", t)
                _state.value = _state.value.copy(busy = false, message = null, error = friendly(t))
            }
        }
    }

    private fun friendly(t: Throwable): String {
        val msg = t.message ?: t.toString()
        return when {
            msg.contains("no TLS stream", true) || msg.contains("TLS", true) -> "TLSエラー: $msg"
            msg.contains("authentication", true) || msg.contains("401", true) ->
                "認証に失敗しました（トークンを確認してください）: $msg"
            msg.contains("not found", true) || msg.contains("404", true) -> "リポジトリが見つかりません: $msg"
            else -> msg
        }
    }

    override fun onCleared() {
        session?.close()
        repo?.close()
        super.onCleared()
    }

    companion object {
        private const val TAG = "Zree"
        private const val KEY_VAULT = "vaultPath"
        private const val KEY_AUTO_ON = "autoSyncEnabled"
        private const val KEY_AUTO_MIN = "autoSyncMinutes"
        private const val KEY_LAST_SYNC = "lastSyncAt"
    }
}
