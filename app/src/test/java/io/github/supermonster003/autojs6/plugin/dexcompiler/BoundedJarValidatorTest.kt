package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.autojs.plugin.dexcompiler.api.DexCompilerErrorCode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.ByteArrayInputStream
import java.nio.file.Files

class BoundedJarValidatorTest {
    @Test
    fun validJarIsCopiedAndMeasured() {
        val root = Files.createTempDirectory("dex-jar-validator-test").toFile()
        try {
            val runtimeFile = root.resolve("runtime.jar").apply { writeBytes(byteArrayOf(9)) }
            val runtime = RuntimeLibrarySet.fromFiles(listOf(runtimeFile))
            val program = TestData.programJar()
            val request = TestData.request(program, runtime)
            val destination = root.resolve("program.jar")

            val result = BoundedJarValidator.copyAndValidate(
                request,
                ByteArrayInputStream(program),
                destination,
                DexCompilerRuntime.capabilities(runtime).limits,
            )

            assertEquals(program.size.toLong(), result.compressedSizeBytes)
            assertEquals(1, result.archiveEntryCount)
            assertEquals(1, result.classEntryCount)
            assertEquals(program.toList(), destination.readBytes().toList())
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun unsafeEntryNameIsRejected() {
        val root = Files.createTempDirectory("dex-jar-name-test").toFile()
        try {
            val runtimeFile = root.resolve("runtime.jar").apply { writeBytes(byteArrayOf(9)) }
            val runtime = RuntimeLibrarySet.fromFiles(listOf(runtimeFile))
            val program = TestData.programJar("../Program.class")
            val failure = assertThrows(DexCompileFailure::class.java) {
                BoundedJarValidator.copyAndValidate(
                    TestData.request(program, runtime),
                    ByteArrayInputStream(program),
                    root.resolve("program.jar"),
                    DexCompilerRuntime.capabilities(runtime).limits,
                )
            }
            assertEquals(DexCompilerErrorCode.INVALID_ARCHIVE, failure.code)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun declaredDigestMismatchIsRejected() {
        val root = Files.createTempDirectory("dex-jar-digest-test").toFile()
        try {
            val runtimeFile = root.resolve("runtime.jar").apply { writeBytes(byteArrayOf(9)) }
            val runtime = RuntimeLibrarySet.fromFiles(listOf(runtimeFile))
            val program = TestData.programJar()
            val different = TestData.programJar(classBytes = byteArrayOf(
                0xca.toByte(), 0xfe.toByte(), 0xba.toByte(), 0xbe.toByte(), 1,
            ))
            val failure = assertThrows(DexCompileFailure::class.java) {
                BoundedJarValidator.copyAndValidate(
                    TestData.request(different, runtime),
                    ByteArrayInputStream(program),
                    root.resolve("program.jar"),
                    DexCompilerRuntime.capabilities(runtime).limits,
                )
            }
            assertEquals(DexCompilerErrorCode.INVALID_REQUEST, failure.code)
        } finally {
            root.deleteRecursively()
        }
    }
}
