package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class PrivateSessionWorkspaceTest {
    @Test
    fun workspaceStaysUnderPrivateRootAndIsRemovedOnClose() {
        val root = Files.createTempDirectory("dex-workspace-test").toFile()
        try {
            val workspace = PrivateSessionWorkspace.createUnder(root.resolve("sessions"))
            val sessionRoot = requireNotNull(workspace.programJar.parentFile)
            assertTrue(sessionRoot.canonicalPath.startsWith(root.canonicalPath))
            assertTrue(workspace.d8OutputDirectory.isDirectory)
            workspace.programJar.writeBytes(byteArrayOf(1))

            workspace.close()

            assertFalse(sessionRoot.exists())
        } finally {
            root.deleteRecursively()
        }
    }
}
