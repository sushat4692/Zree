package im.sush.zree

import java.io.File

/**
 * Local tree folders.
 *
 * Kept free of Android APIs so the deletion path can be tested on the JVM: forgetting a
 * tree deletes its folder, and a half-deleted folder is worse than an error message.
 */
object TreeFiles {

    /** Total bytes under [path] (0 when it does not exist). */
    fun size(path: File): Long {
        if (!path.exists()) return 0
        if (path.isFile) return path.length()
        return path.listFiles()?.sumOf { size(it) } ?: 0
    }

    /**
     * Delete [path] and everything under it.
     *
     * Git keeps objects read-only; deleting them only needs write permission on the parent
     * directory, but make them writable anyway so a retry cannot fail on permissions.
     * Returns true when nothing is left behind.
     */
    fun delete(path: File): Boolean {
        if (!path.exists()) return true
        makeWritable(path)
        val deleted = runCatching { path.deleteRecursively() }.getOrDefault(false)
        return deleted || !path.exists()
    }

    private fun makeWritable(file: File) {
        runCatching { file.setWritable(true) }
        if (file.isDirectory) {
            file.listFiles()?.forEach { makeWritable(it) }
        }
    }

    fun humanSize(bytes: Long): String = when {
        bytes >= 1024L * 1024L -> String.format("%.1fMB", bytes / (1024.0 * 1024.0))
        bytes >= 1024L -> "${bytes / 1024}KB"
        else -> "${bytes}B"
    }
}
