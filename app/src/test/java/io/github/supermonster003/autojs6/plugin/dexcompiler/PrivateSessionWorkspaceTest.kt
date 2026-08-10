package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.nio.file.Files
import java.util.UUID

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

    @Test
    fun startupRecoveryRemovesOnlyCanonicalSessionDirectories() {
        val root = Files.createTempDirectory("dex-workspace-recovery-test").toFile()
        try {
            val sessions = root.resolve("sessions").apply { mkdirs() }
            val stale = sessions.resolve("session-${UUID.randomUUID()}").apply { mkdir() }
            stale.resolve("program.jar").writeBytes(byteArrayOf(1, 2, 3))
            val unrelated = sessions.resolve("keep-me").apply { mkdir() }
            unrelated.resolve("sentinel").writeText("keep")
            val outside = root.resolve("outside").apply { mkdir() }
            outside.resolve("sentinel").writeText("keep")

            PrivateSessionWorkspace.recoverStaleUnder(sessions)

            assertFalse(stale.exists())
            assertTrue(unrelated.resolve("sentinel").isFile)
            assertTrue(outside.resolve("sentinel").isFile)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun startupRecoveryFailsClosedForSessionShapedNonDirectory() {
        val root = Files.createTempDirectory("dex-workspace-invalid-test").toFile()
        try {
            val sessions = root.resolve("sessions").apply { mkdirs() }
            val invalid = sessions.resolve("session-${UUID.randomUUID()}")
            invalid.writeText("not a directory")

            val failure = runCatching {
                PrivateSessionWorkspace.recoverStaleUnder(sessions)
            }.exceptionOrNull()

            assertTrue(failure is IOException)
            assertTrue(invalid.isFile)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun startupRecoveryRejectsNonCanonicalBaseAlias() {
        val root = Files.createTempDirectory("dex-workspace-alias-test").toFile()
        try {
            root.resolve("alias-parent").mkdir()
            root.resolve("sessions").mkdir()
            val aliasedSessions = root.resolve("alias-parent").resolve("..").resolve("sessions")

            val failure = runCatching {
                PrivateSessionWorkspace.recoverStaleUnder(aliasedSessions)
            }.exceptionOrNull()

            assertTrue(failure is IOException)
            assertTrue(root.resolve("sessions").isDirectory)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun processRecoveryRunsOnceAfterSuccessAndRetriesAfterFailure() {
        val recovery = ProcessWorkspaceRecovery()
        var attempts = 0

        val firstFailure = runCatching {
            recovery.ensureRecovered {
                attempts += 1
                throw IOException("injected recovery failure")
            }
        }.exceptionOrNull()
        assertTrue(firstFailure is IOException)

        recovery.ensureRecovered { attempts += 1 }
        recovery.ensureRecovered { attempts += 100 }

        assertEquals(2, attempts)
    }

    @Test
    fun completedProcessRecoveryDoesNotDeleteLaterActiveWorkspace() {
        val root = Files.createTempDirectory("dex-workspace-once-test").toFile()
        try {
            val sessions = root.resolve("sessions")
            val stale = sessions.resolve("session-${UUID.randomUUID()}").apply { mkdirs() }
            stale.resolve("program.jar").writeBytes(byteArrayOf(1))
            val recovery = ProcessWorkspaceRecovery()

            recovery.ensureRecovered { PrivateSessionWorkspace.recoverStaleUnder(sessions) }
            assertFalse(stale.exists())

            val active = PrivateSessionWorkspace.createUnder(sessions)
            val activeRoot = requireNotNull(active.programJar.parentFile)
            recovery.ensureRecovered { PrivateSessionWorkspace.recoverStaleUnder(sessions) }

            assertTrue(activeRoot.isDirectory)
            active.close()
        } finally {
            root.deleteRecursively()
        }
    }
}
