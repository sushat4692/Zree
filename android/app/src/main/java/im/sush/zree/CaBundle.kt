package im.sush.zree

import android.content.Context
import android.util.Log
import java.io.File

/**
 * libgit2 on Android is linked against OpenSSL, which has no built-in trust
 * store. Android keeps its CA certificates as individual hashed PEM files, so
 * we concatenate them into a single bundle once and hand it to libgit2.
 */
object CaBundle {
    private const val FILE = "ca-bundle.pem"
    private val SOURCES = listOf(
        "/apex/com.android.conscrypt/cacerts",
        "/system/etc/security/cacerts",
    )

    fun ensure(context: Context): String? {
        val out = File(context.filesDir, FILE)
        if (out.isFile && out.length() > 0L) return out.absolutePath

        val builder = StringBuilder()
        var count = 0
        for (dir in SOURCES) {
            val files = File(dir).listFiles() ?: continue
            for (f in files) {
                if (!f.isFile) continue
                runCatching {
                    builder.append(f.readText())
                    if (!builder.endsWith("\n")) builder.append('\n')
                    count++
                }
            }
            if (count > 0) break
        }
        if (count == 0) {
            Log.w("Zree", "no system CA certificates found")
            return null
        }
        return runCatching {
            out.writeText(builder.toString())
            Log.i("Zree", "wrote $count CA certificates to ${out.absolutePath}")
            out.absolutePath
        }.getOrNull()
    }
}
