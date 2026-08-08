package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.autojs.plugin.dexcompiler.api.DexRuntimeLibraryFingerprint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.nio.file.Files

class RuntimeLibrarySetTest {
    @Test
    fun identitiesAreOrderedAndContentAddressed() {
        val root = Files.createTempDirectory("dex-runtime-test").toFile()
        try {
            val first = root.resolve("first.jar").apply { writeBytes(byteArrayOf(1, 2, 3)) }
            val second = root.resolve("second.jar").apply { writeBytes(byteArrayOf(4, 5)) }
            val forward = RuntimeLibrarySet.fromFiles(listOf(first, second))
            val reverse = RuntimeLibrarySet.fromFiles(listOf(second, first))

            assertEquals(listOf(3L, 2L), forward.identities.map { it.sizeBytes })
            assertEquals(DexRuntimeLibraryFingerprint.compute(forward.identities), forward.fingerprint)
            assertNotEquals(forward.fingerprint, reverse.fingerprint)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun duplicateCanonicalRuntimeFilesAreRejected() {
        val root = Files.createTempDirectory("dex-runtime-duplicate-test").toFile()
        try {
            val library = root.resolve("runtime.jar").apply { writeBytes(byteArrayOf(1)) }
            assertThrows(IllegalArgumentException::class.java) {
                RuntimeLibrarySet.fromFiles(listOf(library, library.absoluteFile))
            }
        } finally {
            root.deleteRecursively()
        }
    }
}
