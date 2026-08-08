package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.autojs.plugin.dexcompiler.api.DexCompilerErrorCode
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.nio.file.Files
import java.util.zip.ZipInputStream

class DexIndexedOutputPackagerTest {
    @Test
    fun dexEntriesUseNumericOrderAndActualArtifactSummary() {
        val root = Files.createTempDirectory("dex-output-packager-test").toFile()
        try {
            val output = root.resolve("d8").apply { mkdir() }
            repeat(10) { index ->
                val number = index + 1
                val name = if (number == 1) "classes.dex" else "classes$number.dex"
                output.resolve(name).writeBytes(byteArrayOf(number.toByte()))
            }
            val destination = root.resolve("artifact.zip")

            val artifact = DexIndexedOutputPackager.packageOutput(output, destination, 1_000_000L, 64)
            val names = mutableListOf<String>()
            ZipInputStream(destination.inputStream()).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    names += entry.name
                }
            }

            assertEquals(
                listOf("classes.dex") + (2..10).map { "classes$it.dex" },
                names,
            )
            assertEquals(destination.length(), artifact.outputSizeBytes)
            assertEquals(DexHashes.sha256(destination), artifact.outputSha256)
            assertEquals(10, artifact.dexEntryCount)
            assertArrayEquals(destination.readBytes(), artifact.file.readBytes())
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun missingDexIndexIsRejected() {
        val root = Files.createTempDirectory("dex-output-gap-test").toFile()
        try {
            val output = root.resolve("d8").apply { mkdir() }
            output.resolve("classes.dex").writeBytes(byteArrayOf(1))
            output.resolve("classes3.dex").writeBytes(byteArrayOf(3))
            val failure = assertThrows(DexCompileFailure::class.java) {
                DexIndexedOutputPackager.packageOutput(output, root.resolve("artifact.zip"), 1_000_000L, 64)
            }
            assertEquals(DexCompilerErrorCode.INTERNAL, failure.code)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun nonCanonicalDexNameIsRejected() {
        val root = Files.createTempDirectory("dex-output-name-test").toFile()
        try {
            val output = root.resolve("d8").apply { mkdir() }
            output.resolve("classes.dex").writeBytes(byteArrayOf(1))
            output.resolve("classes02.dex").writeBytes(byteArrayOf(2))
            assertThrows(DexCompileFailure::class.java) {
                DexIndexedOutputPackager.packageOutput(output, root.resolve("artifact.zip"), 1_000_000L, 64)
            }
        } finally {
            root.deleteRecursively()
        }
    }
}
