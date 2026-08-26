package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.autojs.plugin.dexcompiler.api.DexCompilerErrorCode
import org.autojs.plugin.dexcompiler.api.DexCompilerFailurePhase
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.nio.charset.StandardCharsets
import java.nio.file.Files

class BoundedJarValidatorTest {
    @Test
    fun validJarIsCopiedAndMeasured() = withFixture("dex-jar-validator-test") { root, runtime ->
        val program = TestData.programJar()
        val destination = root.resolve("program.jar")

        val result = BoundedJarValidator.copyAndValidate(
            TestData.request(program, runtime),
            ByteArrayInputStream(program),
            destination,
            DexCompilerRuntime.capabilities(runtime).limits,
        )

        assertEquals(program.size.toLong(), result.compressedSizeBytes)
        assertEquals(1, result.archiveEntryCount)
        assertEquals(1, result.classEntryCount)
        assertArrayEquals(program, destination.readBytes())
    }

    @Test
    fun deflatedJarWithDataDescriptorIsCopiedAndMeasured() =
        withFixture("dex-jar-descriptor-valid-test") { root, runtime ->
            val program = TestData.programJarWithDataDescriptor()
            val destination = root.resolve("program.jar")

            val result = BoundedJarValidator.copyAndValidate(
                TestData.request(program, runtime),
                ByteArrayInputStream(program),
                destination,
                DexCompilerRuntime.capabilities(runtime).limits,
            )

            assertEquals(program.size.toLong(), result.compressedSizeBytes)
            assertEquals(1, result.archiveEntryCount)
            assertEquals(1, result.classEntryCount)
            assertEquals(VALID_CLASS_BYTES.size.toLong(), result.uncompressedSizeBytes)
            assertEquals(VALID_CLASS_BYTES.size.toLong(), result.totalClassBytes)
            assertArrayEquals(program, destination.readBytes())
        }

    @Test
    fun javaWebSocketStyleBinaryArchiveCommentIsCopiedAndMeasured() =
        withFixture("dex-jar-comment-valid-test") { root, runtime ->
            val comment = byteArrayOf(0x04, 0xf7.toByte(), 0x41, 0x04, 0x00)
            val program = TestData.programJar()
                .patchU16(ZIP_EOCD_SIGNATURE, relativeOffset = 20, value = comment.size) + comment
            val destination = root.resolve("program.jar")

            val result = BoundedJarValidator.copyAndValidate(
                TestData.request(program, runtime),
                ByteArrayInputStream(program),
                destination,
                DexCompilerRuntime.capabilities(runtime).limits,
            )

            assertEquals(program.size.toLong(), result.compressedSizeBytes)
            assertEquals(1, result.archiveEntryCount)
            assertEquals(1, result.classEntryCount)
            assertArrayEquals(program, destination.readBytes())
        }

    @Test
    fun leadingAndTrailingZipEnvelopeDataAreRejected() = withFixture("dex-jar-envelope-test") { root, runtime ->
        val valid = TestData.programJar()
        val cases = listOf(
            "trailing-data" to (valid + byteArrayOf(1, 2, 3)),
            "leading-data" to (byteArrayOf(1, 2, 3) + valid),
        )

        cases.forEachIndexed { index, (label, program) ->
            assertInvalidArchive(label, program, root.resolve("program-$index.jar"), runtime)
        }
    }

    @Test
    fun truncatedZipRecordsAreRejected() = withFixture("dex-jar-truncation-test") { root, runtime ->
        val valid = TestData.programJar()
        val centralOffset = valid.indexOf(ZIP_CENTRAL_SIGNATURE).also {
            check(it >= 0) { "ZIP central-directory signature not found" }
        }
        val cases = listOf(
            "truncated local header" to valid.copyOf(16),
            "truncated central header" to valid.copyOf(centralOffset + 20),
            "truncated EOCD" to valid.copyOf(valid.size - 10),
        )

        cases.forEachIndexed { index, (label, program) ->
            assertInvalidArchive(label, program, root.resolve("program-$index.jar"), runtime)
        }
    }

    @Test
    fun duplicateEntryNameIsRejected() = withFixture("dex-jar-duplicate-test") { root, runtime ->
        val firstName = "org/autojs/test/Program1.class"
        val secondName = "org/autojs/test/Program2.class"
        val program = TestData.storedJar(
            listOf(
                firstName to VALID_CLASS_BYTES,
                secondName to VALID_CLASS_BYTES,
            ),
        ).replacingAll(
            secondName.toByteArray(StandardCharsets.UTF_8),
            firstName.toByteArray(StandardCharsets.UTF_8),
            expectedReplacements = 2,
        )

        assertInvalidArchive("duplicate entry", program, root.resolve("program.jar"), runtime)
    }

    @Test
    fun invalidClassMagicIsRejected() = withFixture("dex-jar-class-magic-test") { root, runtime ->
        val program = TestData.programJar(classBytes = byteArrayOf(0, 1, 2, 3, 4, 5, 6, 7))

        assertInvalidArchive("invalid class magic", program, root.resolve("program.jar"), runtime)
    }

    @Test
    fun unsafeAndNonNfcEntryNamesAreRejected() = withFixture("dex-jar-name-test") { root, runtime ->
        val names = listOf(
            "../Program.class",
            "/Program.class",
            "org\\Program.class",
            "C:Program.class",
            "org//Program.class",
            "org/./Program.class",
            "org/Cafe\u0301.class",
        )

        names.forEachIndexed { index, name ->
            val program = TestData.programJar(name)
            assertInvalidArchive(name, program, root.resolve("program-$index.jar"), runtime)
        }
    }

    @Test
    fun unsupportedCompressionMethodIsRejected() = withFixture("dex-jar-method-test") { root, runtime ->
        val program = TestData.programJar()
            .patchU16(ZIP_LOCAL_SIGNATURE, relativeOffset = 8, value = 99)
            .patchU16(ZIP_CENTRAL_SIGNATURE, relativeOffset = 10, value = 99)

        assertInvalidArchive("unsupported compression", program, root.resolve("program.jar"), runtime)
    }

    @Test
    fun zip64SentinelIsRejected() = withFixture("dex-jar-zip64-test") { root, runtime ->
        val program = TestData.programJar()
            .patchU32(ZIP_CENTRAL_SIGNATURE, relativeOffset = 20, value = 0xffff_ffffL)

        assertInvalidArchive("ZIP64 sentinel", program, root.resolve("program.jar"), runtime)
    }

    @Test
    fun malformedExtraFieldIsRejected() = withFixture("dex-jar-extra-test") { root, runtime ->
        val validExtra = byteArrayOf(0x34, 0x12, 0, 0)
        val malformedExtra = byteArrayOf(0x34, 0x12, 1, 0)
        val program = TestData.programJar(entryExtra = validExtra).replacingAll(
            validExtra,
            malformedExtra,
            expectedReplacements = 2,
        )

        assertInvalidArchive("malformed extra field", program, root.resolve("program.jar"), runtime)
    }

    @Test
    fun malformedDataDescriptorIsRejected() = withFixture("dex-jar-descriptor-test") { root, runtime ->
        val program = TestData.programJarWithDataDescriptor()
            .patchU32(ZIP_DATA_DESCRIPTOR_SIGNATURE, relativeOffset = 4, value = 0L)

        assertInvalidArchive("malformed data descriptor", program, root.resolve("program.jar"), runtime)
    }

    @Test
    fun declaredDigestMismatchIsRejected() = withFixture("dex-jar-digest-test") { root, runtime ->
        val program = TestData.programJar()
        val different = TestData.programJar(
            classBytes = byteArrayOf(
                0xca.toByte(), 0xfe.toByte(), 0xba.toByte(), 0xbe.toByte(), 1,
            ),
        )
        val failure = assertThrows(DexCompileFailure::class.java) {
            BoundedJarValidator.copyAndValidate(
                TestData.request(different, runtime),
                ByteArrayInputStream(program),
                root.resolve("program.jar"),
                DexCompilerRuntime.capabilities(runtime).limits,
            )
        }

        assertEquals(DexCompilerErrorCode.INVALID_REQUEST, failure.code)
        assertEquals(DexCompilerFailurePhase.INPUT_VALIDATION, failure.phase)
    }

    @Test
    fun emptyInputDeletesDestination() = withFixture("dex-jar-empty-test") { root, runtime ->
        val program = TestData.programJar()
        val destination = root.resolve("program.jar").apply { writeBytes(byteArrayOf(9)) }
        val failure = assertThrows(DexCompileFailure::class.java) {
            BoundedJarValidator.copyAndValidate(
                TestData.request(program, runtime),
                ByteArrayInputStream(byteArrayOf()),
                destination,
                DexCompilerRuntime.capabilities(runtime).limits,
            )
        }

        assertEquals(DexCompilerErrorCode.INVALID_ARCHIVE, failure.code)
        assertEquals(DexCompilerFailurePhase.INPUT_VALIDATION, failure.phase)
        assertFalse(destination.exists())
    }

    @Test
    fun copyFailureDeletesPartialDestination() = withFixture("dex-jar-copy-failure-test") { root, runtime ->
        val program = TestData.programJar()
        val destination = root.resolve("program.jar").apply { writeBytes(byteArrayOf(9)) }

        assertThrows(IOException::class.java) {
            BoundedJarValidator.copyAndValidate(
                TestData.request(program, runtime),
                FailingInputStream(program.copyOfRange(0, 16)),
                destination,
                DexCompilerRuntime.capabilities(runtime).limits,
            )
        }
        assertFalse(destination.exists())
    }

    private fun assertInvalidArchive(
        label: String,
        program: ByteArray,
        destination: File,
        runtime: RuntimeLibrarySet,
    ) {
        val failure = assertThrows("$label should be rejected", DexCompileFailure::class.java) {
            BoundedJarValidator.copyAndValidate(
                TestData.request(program, runtime),
                ByteArrayInputStream(program),
                destination,
                DexCompilerRuntime.capabilities(runtime).limits,
            )
        }
        assertEquals(label, DexCompilerErrorCode.INVALID_ARCHIVE, failure.code)
        assertEquals(label, DexCompilerFailurePhase.INPUT_VALIDATION, failure.phase)
    }

    private fun withFixture(
        prefix: String,
        block: (root: File, runtime: RuntimeLibrarySet) -> Unit,
    ) {
        val root = Files.createTempDirectory(prefix).toFile()
        try {
            val runtimeFile = root.resolve("runtime.jar").apply { writeBytes(byteArrayOf(9)) }
            block(root, RuntimeLibrarySet.fromFiles(listOf(runtimeFile)))
        } finally {
            root.deleteRecursively()
        }
    }
}

private class FailingInputStream(private val prefix: ByteArray) : InputStream() {
    private var offset = 0

    override fun read(): Int {
        if (offset >= prefix.size) throw IOException("injected copy failure")
        return prefix[offset++].toInt() and 0xff
    }

    override fun read(destination: ByteArray, destinationOffset: Int, length: Int): Int {
        if (offset >= prefix.size) throw IOException("injected copy failure")
        val copied = minOf(length, prefix.size - offset)
        prefix.copyInto(destination, destinationOffset, offset, offset + copied)
        offset += copied
        return copied
    }
}

private fun ByteArray.patchU16(signature: ByteArray, relativeOffset: Int, value: Int): ByteArray {
    require(value in 0..0xffff)
    return copyOf().also { result ->
        val offset = result.indexOf(signature)
        check(offset >= 0) { "ZIP signature not found" }
        result[offset + relativeOffset] = value.toByte()
        result[offset + relativeOffset + 1] = (value ushr 8).toByte()
    }
}

private fun ByteArray.patchU32(signature: ByteArray, relativeOffset: Int, value: Long): ByteArray {
    require(value in 0..0xffff_ffffL)
    return copyOf().also { result ->
        val offset = result.indexOf(signature)
        check(offset >= 0) { "ZIP signature not found" }
        repeat(4) { index ->
            result[offset + relativeOffset + index] = (value ushr (index * 8)).toByte()
        }
    }
}

private fun ByteArray.replacingAll(
    old: ByteArray,
    replacement: ByteArray,
    expectedReplacements: Int,
): ByteArray {
    require(old.isNotEmpty() && old.size == replacement.size)
    val result = copyOf()
    var cursor = 0
    var replacements = 0
    while (cursor <= result.size - old.size) {
        val index = result.indexOf(old, cursor)
        if (index < 0) break
        replacement.copyInto(result, index)
        replacements++
        cursor = index + replacement.size
    }
    check(replacements == expectedReplacements) {
        "Expected $expectedReplacements replacements, found $replacements"
    }
    return result
}

private fun ByteArray.indexOf(sequence: ByteArray, startIndex: Int = 0): Int {
    if (sequence.isEmpty()) return startIndex.coerceAtMost(size)
    for (index in startIndex..size - sequence.size) {
        if (sequence.indices.all { this[index + it] == sequence[it] }) return index
    }
    return -1
}

private val VALID_CLASS_BYTES = byteArrayOf(
    0xca.toByte(), 0xfe.toByte(), 0xba.toByte(), 0xbe.toByte(), 0, 0, 0, 52,
)
private val ZIP_LOCAL_SIGNATURE = byteArrayOf(0x50, 0x4b, 0x03, 0x04)
private val ZIP_CENTRAL_SIGNATURE = byteArrayOf(0x50, 0x4b, 0x01, 0x02)
private val ZIP_EOCD_SIGNATURE = byteArrayOf(0x50, 0x4b, 0x05, 0x06)
private val ZIP_DATA_DESCRIPTOR_SIGNATURE = byteArrayOf(0x50, 0x4b, 0x07, 0x08)
