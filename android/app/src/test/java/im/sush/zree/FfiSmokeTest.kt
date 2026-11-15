package im.sush.zree

import org.junit.Test

class FfiSmokeTest {
    @Test
    fun core_loads() {
        println("jna.library.path=" + System.getProperty("jna.library.path"))
        println("java.library.path=" + System.getProperty("java.library.path"))
        try {
            println("listAction(- a) = " + uniffi.zree_core.listAction("- a"))
        } catch (t: Throwable) {
            println("FAILED: " + t)
            t.printStackTrace()
        }
    }
}
