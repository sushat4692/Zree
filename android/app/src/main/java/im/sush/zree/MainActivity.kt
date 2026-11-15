package im.sush.zree

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import uniffi.zree_core.GitRepo
import uniffi.zree_core.ZreeSession
import uniffi.zree_core.isGitRepo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Phase-1 spike screen: proves the Rust core loads and runs on the device
 * (uniffi + JNA + libgit2 + OpenSSL), before any real UI is written.
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { ZreeApp() }
    }
}

@Composable
fun ZreeApp() {
    val context = LocalContext.current
    var output by remember { mutableStateOf("実行中…") }

    LaunchedEffect(Unit) {
        output = withContext(Dispatchers.IO) {
            val log = StringBuilder()
            fun line(s: String) = log.append(s).append('\n')

            try {
                line("== uniffi / Rust core ==")
                val dir = File(context.filesDir, "smoke-vault").apply { mkdirs() }
                File(dir, "テスト ノート.md").writeText("#お客様打合せ #テスト\n本文です。\n")
                File(dir, "メモ 2.md").writeText("- [ ] 課題\n月イチ面談\n")
                File(dir, "読書メモ.md").writeText("#読書\nフォームの設計について\n")

                val session = ZreeSession.open(dir.absolutePath)
                line("notes: ${session.list().size}")
                line("search 'テスト': ${session.search("テスト", emptyList(), 10u).size} hits")
                line("search '面談': ${session.search("面談", emptyList(), 10u).size} hits")
                line("tags: ${session.tags().joinToString(", ") { "#${it.tag}x${it.count}" }}")
                line("blocks(テスト ノート): ${session.blocks("テスト ノート.md").size}")
                line("image srcs: ${session.imageSources("テスト ノート.md").size}")
                session.close()

                line("")
                line("== libgit2 ==")
                line("isGitRepo(before): ${isGitRepo(dir.absolutePath)}")
                val repo = GitRepo.ensure(dir.absolutePath)
                line("isGitRepo(after): ${isGitRepo(dir.absolutePath)}")
                val status = repo.status()
                line("branch=${status.branch} changed=${status.changed} ahead=${status.ahead} behind=${status.behind}")

                val oid = repo.commitAll("smoke: commit from device")
                line("commit: ${oid?.take(7) ?: "nothing to commit"}")
                val after = repo.status()
                line("after commit: changed=${after.changed} conflicts=${after.conflicts.size}")
                line("log: ${repo.log(3u).map { it.summary }}")
                repo.close()

                line("")
                line("OK — core works on device")
            } catch (t: Throwable) {
                line("")
                line("FAILED: ${t::class.simpleName}: ${t.message}")
                line(t.stackTraceToString().lines().take(8).joinToString("\n"))
            }
            log.toString()
        }
    }

    MaterialTheme {
        Surface(modifier = Modifier.fillMaxSize()) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp)
            ) {
                Text("Zree spike", style = MaterialTheme.typography.titleMedium)
                Text(output, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}
