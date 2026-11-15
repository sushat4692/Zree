package im.sush.zree

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class TreeFilesTest {

    @get:Rule
    val temp = TemporaryFolder()

    @Test
    fun deletes_a_tree_including_read_only_git_objects() {
        val root = temp.newFolder("vault")
        File(root, "notes").mkdirs()
        File(root, "notes/ノート.md").writeText("本文")
        val objectFile = File(root, ".git/objects/ab/cdef").apply { parentFile.mkdirs() }
        objectFile.writeText("object")
        objectFile.setReadOnly()

        assertTrue(TreeFiles.size(root) > 0)
        assertTrue(TreeFiles.delete(root))
        assertFalse(root.exists())
    }

    @Test
    fun deleting_a_missing_tree_is_not_an_error() {
        assertTrue(TreeFiles.delete(File(temp.root, "nope")))
        assertEquals(0, TreeFiles.size(File(temp.root, "nope")))
    }

    @Test
    fun size_and_human_readable_units() {
        val root = temp.newFolder("v")
        File(root, "a.md").writeText("x".repeat(2048))
        assertEquals(2048, TreeFiles.size(root))
        assertEquals("2KB", TreeFiles.humanSize(2048))
        assertEquals("1.0MB", TreeFiles.humanSize(1024 * 1024))
    }
}
