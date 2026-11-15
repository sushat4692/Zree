package im.sush.zree

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.zree_core.GitRepo
import uniffi.zree_core.GitStatus
import uniffi.zree_core.NoteMeta
import uniffi.zree_core.TagCount
import uniffi.zree_core.ZreeSession
import uniffi.zree_core.isGitRepo
import java.io.File

data class Row(
    val id: String,
    val title: String,
    val snippet: String,
    val tags: List<String>,
    val mtimeMs: Long,
)

enum class Screen { Setup, List, Editor }

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
    val git: GitStatus? = null,
    val busy: Boolean = false,
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
    private var dirty = false

    private val _state = MutableStateFlow(UiState())
    val state = _state.asStateFlow()

    init {
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
        val s = session ?: return@io
        val body = s.read(id)
        val row = _state.value.rows.firstOrNull { it.id == id }
        seenMtime = row?.mtimeMs ?: 0L
        dirty = false
        _state.value = _state.value.copy(
            screen = Screen.Editor,
            selectedId = id,
            title = row?.title ?: id.removeSuffix(".md"),
            draft = body,
        )
    }

    fun setDraft(text: String) {
        dirty = true
        _state.value = _state.value.copy(draft = text)
        saveJob?.cancel()
        saveJob = viewModelScope.launch {
            delay(700)
            save()
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
            _state.value = _state.value.copy(screen = Screen.List, selectedId = null, draft = "")
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

    fun sync() = io {
        val r = repo ?: return@io
        save()
        _state.value = _state.value.copy(busy = true, message = "同期中…")
        try {
            val report = r.sync("zree: sync from android")
            _state.value = _state.value.copy(
                busy = false,
                message = if (report.conflicts.isEmpty()) "同期しました" else "衝突 ${report.conflicts.size} 件",
                error = if (report.conflicts.isEmpty()) null else "衝突を解決してください: ${report.conflicts.joinToString(", ")}",
            )
            refresh()
            _state.value = _state.value.copy(git = r.status())
        } catch (t: Throwable) {
            _state.value = _state.value.copy(busy = false, message = null, error = t.message ?: t.toString())
        }
    }

    fun dismissMessage() {
        _state.value = _state.value.copy(message = null, error = null)
    }

    // MARK: - plumbing

    private fun io(block: suspend () -> Unit) {
        viewModelScope.launch(Dispatchers.IO) {
            runCatching { block() }.onFailure { t ->
                _state.value = _state.value.copy(busy = false, message = null, error = t.message ?: t.toString())
            }
        }
    }

    override fun onCleared() {
        session?.close()
        repo?.close()
        super.onCleared()
    }

    companion object {
        private const val KEY_VAULT = "vaultPath"
    }
}
