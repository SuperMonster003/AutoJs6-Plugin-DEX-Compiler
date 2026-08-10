package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.autojs.plugin.dexcompiler.api.DexCompilerErrorCode
import org.autojs.plugin.dexcompiler.api.DexCompilerFailurePhase
import org.autojs.plugin.dexcompiler.api.DexCompilerResourceLimits
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class BoundedJarValidatorLimitsTest {
    @Test
    fun compressedProgramSizeHonorsInclusiveBoundary() = withFixture("compressed-limit") { root, runtime ->
        val program = storedJar(listOf(CLASS_NAME to validClass(8)))
        val exactLimits = limits(runtime).copy(maxCompressedProgramBytes = program.size.toLong())

        assertValidated(
            program = program,
            destination = root.resolve("exact.jar"),
            runtime = runtime,
            limits = exactLimits,
            expectedEntries = 1,
            expectedClasses = 1,
            expectedUncompressedBytes = 8,
            expectedClassBytes = 8,
        )

        val rejectedDestination = root.resolve("exceeded.jar")
        assertRejected(
            program = program,
            destination = rejectedDestination,
            runtime = runtime,
            limits = exactLimits.copy(maxCompressedProgramBytes = program.size.toLong() - 1L),
            expectedCode = DexCompilerErrorCode.INPUT_TOO_LARGE,
            expectedMessage = "Program archive exceeds the provider limit",
        )
        assertFalse(rejectedDestination.exists())
    }

    @Test
    fun archiveEntryCountHonorsInclusiveBoundary() = withFixture("entry-count-limit") { root, runtime ->
        val program = storedJar(
            listOf(
                CLASS_NAME to validClass(8),
                "assets/value.bin" to byteArrayOf(1, 2, 3),
            ),
        )
        val exactLimits = limits(runtime).copy(maxArchiveEntries = 2)

        assertValidated(
            program = program,
            destination = root.resolve("exact.jar"),
            runtime = runtime,
            limits = exactLimits,
            expectedEntries = 2,
            expectedClasses = 1,
            expectedUncompressedBytes = 11,
            expectedClassBytes = 8,
        )
        assertRejected(
            program = program,
            destination = root.resolve("exceeded.jar"),
            runtime = runtime,
            limits = exactLimits.copy(maxArchiveEntries = 1),
            expectedCode = DexCompilerErrorCode.INVALID_ARCHIVE,
        )
    }

    @Test
    fun uncompressedProgramSizeHonorsInclusiveBoundary() =
        withFixture("uncompressed-limit") { root, runtime ->
            val program = storedJar(
                listOf(
                    CLASS_NAME to validClass(8),
                    "assets/value.bin" to byteArrayOf(1, 2, 3, 4, 5),
                ),
            )
            val exactLimits = limits(runtime).copy(maxUncompressedProgramBytes = 13)

            assertValidated(
                program = program,
                destination = root.resolve("exact.jar"),
                runtime = runtime,
                limits = exactLimits,
                expectedEntries = 2,
                expectedClasses = 1,
                expectedUncompressedBytes = 13,
                expectedClassBytes = 8,
            )
            assertRejected(
                program = program,
                destination = root.resolve("exceeded.jar"),
                runtime = runtime,
                limits = exactLimits.copy(maxUncompressedProgramBytes = 12),
                expectedCode = DexCompilerErrorCode.INVALID_ARCHIVE,
                expectedMessage = "JAR uncompressed data exceeds the provider limit",
            )
        }

    @Test
    fun singleClassSizeHonorsInclusiveBoundary() = withFixture("single-class-limit") { root, runtime ->
        val program = storedJar(listOf(CLASS_NAME to validClass(12)))
        val exactLimits = limits(runtime).copy(maxSingleClassBytes = 12)

        assertValidated(
            program = program,
            destination = root.resolve("exact.jar"),
            runtime = runtime,
            limits = exactLimits,
            expectedEntries = 1,
            expectedClasses = 1,
            expectedUncompressedBytes = 12,
            expectedClassBytes = 12,
        )
        assertRejected(
            program = program,
            destination = root.resolve("exceeded.jar"),
            runtime = runtime,
            limits = exactLimits.copy(maxSingleClassBytes = 11),
            expectedCode = DexCompilerErrorCode.INVALID_ARCHIVE,
            expectedMessage = "A class entry exceeds the provider limit",
        )
    }

    @Test
    fun totalClassSizeHonorsInclusiveBoundary() = withFixture("total-class-limit") { root, runtime ->
        val program = storedJar(
            listOf(
                "classes/First.class" to validClass(8),
                "classes/Second.class" to validClass(9),
                "assets/value.bin" to byteArrayOf(1, 2, 3),
            ),
        )
        val exactLimits = limits(runtime).copy(maxTotalClassBytes = 17)

        assertValidated(
            program = program,
            destination = root.resolve("exact.jar"),
            runtime = runtime,
            limits = exactLimits,
            expectedEntries = 3,
            expectedClasses = 2,
            expectedUncompressedBytes = 20,
            expectedClassBytes = 17,
        )
        assertRejected(
            program = program,
            destination = root.resolve("exceeded.jar"),
            runtime = runtime,
            limits = exactLimits.copy(maxTotalClassBytes = 16),
            expectedCode = DexCompilerErrorCode.INVALID_ARCHIVE,
            expectedMessage = "JAR class data exceeds the provider limit",
        )
    }

    @Test
    fun entryAndAggregateCompressionRatiosAcceptExactLimit() =
        withFixture("compression-ratio-limit") { root, runtime ->
            val program = deflatedJar(
                listOf(
                    "classes/First.class" to validClass(EXACT_RATIO_CLASS_BYTES),
                    "classes/Second.class" to validClass(EXACT_RATIO_CLASS_BYTES),
                ),
            )
            val compressedSizes = centralCompressedSizes(program)
            assertEquals(listOf(22L, 22L), compressedSizes)
            assertTrue(compressedSizes.all { EXACT_RATIO_CLASS_BYTES.toLong() == it * MAX_COMPRESSION_RATIO })
            // The entry and aggregate policies use the same ratio. Two entries exactly at the
            // entry boundary therefore put the aggregate content ratio exactly at its boundary too.
            assertEquals(
                compressedSizes.sum() * MAX_COMPRESSION_RATIO,
                EXACT_RATIO_CLASS_BYTES.toLong() * compressedSizes.size,
            )

            assertValidated(
                program = program,
                destination = root.resolve("exact.jar"),
                runtime = runtime,
                limits = limits(runtime),
                expectedEntries = 2,
                expectedClasses = 2,
                expectedUncompressedBytes = EXACT_RATIO_CLASS_BYTES.toLong() * 2L,
                expectedClassBytes = EXACT_RATIO_CLASS_BYTES.toLong() * 2L,
            )
        }

    @Test
    fun compressionBombExceedingEntryRatioIsRejected() =
        withFixture("compression-bomb-limit") { root, runtime ->
            val classBytes = validClass(COMPRESSION_BOMB_CLASS_BYTES)
            val program = deflatedJar(listOf(CLASS_NAME to classBytes))
            val compressedSize = centralCompressedSizes(program).single()
            assertEquals(20L, compressedSize)
            assertTrue(classBytes.size.toLong() > compressedSize * MAX_COMPRESSION_RATIO)

            assertRejected(
                program = program,
                destination = root.resolve("rejected.jar"),
                runtime = runtime,
                limits = limits(runtime),
                expectedCode = DexCompilerErrorCode.INVALID_ARCHIVE,
                expectedMessage = "JAR entry compression ratio exceeds the provider limit",
            )
        }

    private fun assertValidated(
        program: ByteArray,
        destination: File,
        runtime: RuntimeLibrarySet,
        limits: DexCompilerResourceLimits,
        expectedEntries: Int,
        expectedClasses: Int,
        expectedUncompressedBytes: Long,
        expectedClassBytes: Long,
    ) {
        val result = BoundedJarValidator.copyAndValidate(
            TestData.request(program, runtime),
            ByteArrayInputStream(program),
            destination,
            limits,
        )

        assertEquals(program.size.toLong(), result.compressedSizeBytes)
        assertEquals(expectedEntries, result.archiveEntryCount)
        assertEquals(expectedClasses, result.classEntryCount)
        assertEquals(expectedUncompressedBytes, result.uncompressedSizeBytes)
        assertEquals(expectedClassBytes, result.totalClassBytes)
    }

    private fun assertRejected(
        program: ByteArray,
        destination: File,
        runtime: RuntimeLibrarySet,
        limits: DexCompilerResourceLimits,
        expectedCode: DexCompilerErrorCode,
        expectedMessage: String? = null,
    ) {
        val failure = assertThrows(DexCompileFailure::class.java) {
            BoundedJarValidator.copyAndValidate(
                TestData.request(program, runtime),
                ByteArrayInputStream(program),
                destination,
                limits,
            )
        }

        assertEquals(expectedCode, failure.code)
        assertEquals(DexCompilerFailurePhase.INPUT_VALIDATION, failure.phase)
        expectedMessage?.let { assertEquals(it, failure.message) }
    }

    private fun limits(runtime: RuntimeLibrarySet): DexCompilerResourceLimits =
        DexCompilerRuntime.capabilities(runtime).limits

    private fun withFixture(
        prefix: String,
        block: (root: File, runtime: RuntimeLibrarySet) -> Unit,
    ) {
        val root = Files.createTempDirectory("dex-validator-$prefix").toFile()
        try {
            val runtimeFile = root.resolve("runtime.jar").apply { writeBytes(byteArrayOf(9)) }
            block(root, RuntimeLibrarySet.fromFiles(listOf(runtimeFile)))
        } finally {
            root.deleteRecursively()
        }
    }
}

private fun storedJar(entries: List<Pair<String, ByteArray>>): ByteArray = jar(entries, stored = true)

private fun deflatedJar(entries: List<Pair<String, ByteArray>>): ByteArray = jar(entries, stored = false)

private fun jar(entries: List<Pair<String, ByteArray>>, stored: Boolean): ByteArray =
    ByteArrayOutputStream().use { bytes ->
        ZipOutputStream(bytes).use { zip ->
            entries.forEach { (name, content) ->
                val entry = ZipEntry(name).apply {
                    method = if (stored) ZipEntry.STORED else ZipEntry.DEFLATED
                    time = DOS_EPOCH_MILLIS
                    extra = byteArrayOf()
                    if (stored) {
                        size = content.size.toLong()
                        compressedSize = content.size.toLong()
                        crc = CRC32().apply { update(content) }.value
                    }
                }
                zip.putNextEntry(entry)
                zip.write(content)
                zip.closeEntry()
            }
        }
        bytes.toByteArray()
    }

private fun validClass(size: Int): ByteArray {
    require(size >= CLASS_MAGIC.size)
    return ByteArray(size).also { CLASS_MAGIC.copyInto(it) }
}

private fun centralCompressedSizes(archive: ByteArray): List<Long> {
    val eocdOffset = archive.lastIndexOf(EOCD_SIGNATURE)
    check(eocdOffset >= 0) { "EOCD record not found" }
    val entryCount = archive.u16(eocdOffset + 10)
    var cursor = archive.u32(eocdOffset + 16).toInt()
    return buildList(entryCount) {
        repeat(entryCount) {
            check(archive.matchesAt(cursor, CENTRAL_SIGNATURE)) { "Central-directory record not found" }
            add(archive.u32(cursor + 20))
            val nameLength = archive.u16(cursor + 28)
            val extraLength = archive.u16(cursor + 30)
            val commentLength = archive.u16(cursor + 32)
            cursor += CENTRAL_HEADER_SIZE + nameLength + extraLength + commentLength
        }
    }
}

private fun ByteArray.lastIndexOf(sequence: ByteArray): Int {
    for (offset in size - sequence.size downTo 0) {
        if (matchesAt(offset, sequence)) return offset
    }
    return -1
}

private fun ByteArray.matchesAt(offset: Int, sequence: ByteArray): Boolean =
    offset >= 0 && offset <= size - sequence.size && sequence.indices.all { this[offset + it] == sequence[it] }

private fun ByteArray.u16(offset: Int): Int =
    (this[offset].toInt() and 0xff) or ((this[offset + 1].toInt() and 0xff) shl 8)

private fun ByteArray.u32(offset: Int): Long =
    (u16(offset).toLong() or (u16(offset + 2).toLong() shl 16)) and 0xffff_ffffL

private const val CLASS_NAME = "org/autojs/test/Program.class"
private const val EXACT_RATIO_CLASS_BYTES = 2_200
private const val COMPRESSION_BOMB_CLASS_BYTES = 2_069
private const val MAX_COMPRESSION_RATIO = 100L
private const val CENTRAL_HEADER_SIZE = 46
private const val DOS_EPOCH_MILLIS = 315_532_800_000L
private val CLASS_MAGIC = byteArrayOf(0xca.toByte(), 0xfe.toByte(), 0xba.toByte(), 0xbe.toByte())
private val CENTRAL_SIGNATURE = byteArrayOf(0x50, 0x4b, 0x01, 0x02)
private val EOCD_SIGNATURE = byteArrayOf(0x50, 0x4b, 0x05, 0x06)
