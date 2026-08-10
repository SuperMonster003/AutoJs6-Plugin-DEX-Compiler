package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.autojs.plugin.dexcompiler.api.DexCompilerErrorCode
import org.autojs.plugin.dexcompiler.api.DexCompilerFailurePhase
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.util.Random

class StrictJarZipFramingAdversarialTest {
    @Test
    fun eocdCountsAndCentralBoundsMismatchesAreRejected() = withArchiveFile("dex-zip-eocd-matrix") { file ->
        val valid = TestData.programJar()
        val eocd = valid.size - TEST_ZIP_EOCD_SIZE
        val entryCount = valid.readU16(eocd + 10)
        val centralSize = valid.readU32(eocd + 12)
        val centralOffset = valid.readU32(eocd + 16)
        val cases = listOf(
            "entries-on-disk" to valid.patchU16(eocd + 8, entryCount + 1),
            "total-entry-count" to valid.patchU16(eocd + 10, entryCount + 1),
            "central-size" to valid.patchU32(eocd + 12, centralSize + 1),
            "central-offset" to valid.patchU32(eocd + 16, centralOffset + 1),
        )

        cases.forEach { (label, archive) -> assertFramingRejected(label, archive, file) }
    }

    @Test
    fun truncatedLocalAndCentralRecordsAreRejectedWithIntactEocd() =
        withArchiveFile("dex-zip-structured-truncation") { file ->
            val valid = TestData.programJar()
            val cases = listOf(
                Triple(
                    "truncated local header",
                    valid.truncateLocalHeaderRetainingCentralDirectory(),
                    "Local and central JAR entry names disagree",
                ),
                Triple(
                    "truncated central header",
                    valid.truncateCentralHeaderRetainingEocd(),
                    "central-directory header exceeds the JAR container",
                ),
            )

            cases.forEach { (label, archive, expectedMessage) ->
                val eocd = archive.size - TEST_ZIP_EOCD_SIZE
                check(archive.matchesAt(eocd, TEST_ZIP_EOCD_SIGNATURE)) {
                    "$label fixture must retain an EOCD at the exact end"
                }
                assertFramingRejected(label, archive, file, expectedMessage)
            }
        }

    @Test
    fun localAndCentralMetadataMismatchesAreRejected() = withArchiveFile("dex-zip-metadata-matrix") { file ->
        val valid = TestData.programJar()
        val central = valid.findSignature(TEST_ZIP_CENTRAL_SIGNATURE)
        val centralName = central + TEST_ZIP_CENTRAL_HEADER_SIZE
        val cases = listOf(
            "entry-name" to valid.flipBit(centralName, 0),
            "flags" to valid.patchU16(central + 8, valid.readU16(central + 8) xor 0x0008),
            "method" to valid.patchU16(central + 10, TEST_ZIP_METHOD_DEFLATED),
            "CRC-32" to valid.patchU32(central + 16, valid.readU32(central + 16) xor 1L),
            "compressed-size" to valid.patchU32(central + 20, valid.readU32(central + 20) + 1),
            "uncompressed-size" to valid.patchU32(central + 24, valid.readU32(central + 24) + 1),
        )

        cases.forEach { (label, archive) -> assertFramingRejected(label, archive, file) }
    }

    @Test
    fun zip64MultiDiskAndEncryptedMetadataAreRejected() =
        withArchiveFile("dex-zip-forbidden-metadata-matrix") { file ->
            val valid = TestData.programJar()
            val central = valid.findSignature(TEST_ZIP_CENTRAL_SIGNATURE)
            val eocd = valid.size - TEST_ZIP_EOCD_SIZE
            val archiveWithExtra = TestData.programJar(entryExtra = byteArrayOf(0x34, 0x12, 0, 0))
            val localExtra = TEST_ZIP_LOCAL_HEADER_SIZE + archiveWithExtra.readU16(26)
            val cases = listOf(
                "ZIP64-extra" to archiveWithExtra.patchU16(localExtra, TEST_ZIP64_EXTRA_ID),
                "EOCD-disk-number" to valid.patchU16(eocd + 4, 1),
                "EOCD-central-disk" to valid.patchU16(eocd + 6, 1),
                "entry-disk-start" to valid.patchU16(central + 34, 1),
                "encrypted-entry" to valid.patchU16(central + 8, valid.readU16(central + 8) or 0x0001),
            )

            cases.forEach { (label, archive) -> assertFramingRejected(label, archive, file) }
        }

    @Test
    fun localRecordGapsOverlapsAndOffsetDisorderAreRejected() =
        withArchiveFile("dex-zip-local-offset-matrix") { file ->
            val valid = TestData.storedJar(
                listOf(
                    "org/autojs/test/First.class" to TEST_VALID_CLASS_BYTES,
                    "org/autojs/test/Second.class" to TEST_VALID_CLASS_BYTES,
                ),
            )
            val centralEntries = valid.findAllSignatures(TEST_ZIP_CENTRAL_SIGNATURE)
            check(centralEntries.size == 2) { "Expected two central-directory entries" }
            val secondCentral = centralEntries[1]
            val secondLocalOffset = valid.readU32(secondCentral + 42)
            val cases = listOf(
                "gap-before-second-local-record" to
                    valid.patchU32(secondCentral + 42, secondLocalOffset + 1),
                "overlap-before-second-local-record" to
                    valid.patchU32(secondCentral + 42, secondLocalOffset - 1),
                "duplicate-or-out-of-order-local-offset" to
                    valid.patchU32(secondCentral + 42, 0),
            )

            cases.forEach { (label, archive) -> assertFramingRejected(label, archive, file) }
        }

    @Test(timeout = MUTATION_TIMEOUT_MILLIS)
    fun fixedSeedMetadataMutationsAreBoundedAndRejected() =
        withArchiveFile("dex-zip-fixed-seed-mutation") { file ->
            val valid = TestData.programJar()
            val targets = guardedMetadataOffsets(valid)
            val random = Random(MUTATION_SEED)

            repeat(MUTATION_CASES) { caseIndex ->
                val offset = targets[random.nextInt(targets.size)]
                val bit = random.nextInt(Byte.SIZE_BITS)
                val mutated = valid.flipBit(offset, bit)
                assertFramingRejected(
                    "fixed-seed mutation case $caseIndex at offset $offset bit $bit",
                    mutated,
                    file,
                )
            }
        }

    private fun guardedMetadataOffsets(archive: ByteArray): IntArray {
        val central = archive.findSignature(TEST_ZIP_CENTRAL_SIGNATURE)
        val eocd = archive.size - TEST_ZIP_EOCD_SIZE
        val localNameLength = archive.readU16(26)
        val centralNameLength = archive.readU16(central + 28)
        return buildList<Int> {
            addAll(0 until 4) // local signature
            addAll(6 until 10) // local flags and method
            addAll(14 until 30) // local CRC, sizes, and name/extra lengths
            addAll(TEST_ZIP_LOCAL_HEADER_SIZE until TEST_ZIP_LOCAL_HEADER_SIZE + localNameLength)
            addAll(central until central + 4) // central signature
            addAll(central + 8 until central + 12) // central flags and method
            addAll(central + 16 until central + 36) // CRC, sizes, lengths, and disk start
            addAll(central + 42 until central + 46) // local-header offset
            addAll(
                central + TEST_ZIP_CENTRAL_HEADER_SIZE until
                    central + TEST_ZIP_CENTRAL_HEADER_SIZE + centralNameLength,
            )
            addAll(eocd until eocd + TEST_ZIP_EOCD_SIZE) // all EOCD fields are guarded
        }.toIntArray()
    }

    private fun assertFramingRejected(
        label: String,
        archive: ByteArray,
        file: File,
        expectedMessage: String? = null,
    ) {
        file.writeBytes(archive)
        val failure = assertThrows("$label should be rejected", DexCompileFailure::class.java) {
            StrictJarZipFraming.validate(file, TEST_MAXIMUM_ENTRIES)
        }
        assertEquals(label, DexCompilerErrorCode.INVALID_ARCHIVE, failure.code)
        assertEquals(label, DexCompilerFailurePhase.INPUT_VALIDATION, failure.phase)
        expectedMessage?.let { assertEquals(label, it, failure.message) }
    }

    private fun withArchiveFile(prefix: String, block: (File) -> Unit) {
        val root = Files.createTempDirectory(prefix).toFile()
        try {
            block(root.resolve("program.jar"))
        } finally {
            root.deleteRecursively()
        }
    }
}

private fun ByteArray.truncateLocalHeaderRetainingCentralDirectory(): ByteArray {
    val eocd = size - TEST_ZIP_EOCD_SIZE
    val centralOffset = readU32(eocd + 16).toInt()
    val retainedLocalPrefix = copyOfRange(0, TEST_TRUNCATED_LOCAL_HEADER_SIZE)
    val centralAndEocd = copyOfRange(centralOffset, size)
    // Local extraLength lands on the central DOS-time bytes after truncation. Pin those otherwise
    // irrelevant central bytes so the local-parser assertion is independent of the JVM timezone.
    val result = (retainedLocalPrefix + centralAndEocd).patchU16(
        TEST_TRUNCATED_LOCAL_HEADER_SIZE + TEST_ZIP_CENTRAL_DOS_TIME_OFFSET,
        0,
    )
    val newEocd = result.size - TEST_ZIP_EOCD_SIZE
    return result.patchU32(newEocd + 16, TEST_TRUNCATED_LOCAL_HEADER_SIZE.toLong())
}

private fun ByteArray.truncateCentralHeaderRetainingEocd(): ByteArray {
    val eocd = size - TEST_ZIP_EOCD_SIZE
    val centralOffset = readU32(eocd + 16).toInt()
    val retainedPrefix = copyOfRange(0, centralOffset + TEST_TRUNCATED_CENTRAL_HEADER_SIZE)
    val result = retainedPrefix + copyOfRange(eocd, size)
    val newEocd = result.size - TEST_ZIP_EOCD_SIZE
    return result.patchU32(newEocd + 12, TEST_TRUNCATED_CENTRAL_HEADER_SIZE.toLong())
}

private fun ByteArray.patchU16(offset: Int, value: Int): ByteArray {
    require(offset >= 0 && offset <= size - 2)
    require(value in 0..0xffff)
    return copyOf().also { result ->
        result[offset] = value.toByte()
        result[offset + 1] = (value ushr 8).toByte()
    }
}

private fun ByteArray.patchU32(offset: Int, value: Long): ByteArray {
    require(offset >= 0 && offset <= size - 4)
    require(value in 0..0xffff_ffffL)
    return copyOf().also { result ->
        repeat(4) { index -> result[offset + index] = (value ushr (index * 8)).toByte() }
    }
}

private fun ByteArray.flipBit(offset: Int, bit: Int): ByteArray {
    require(offset in indices)
    require(bit in 0 until Byte.SIZE_BITS)
    return copyOf().also { result ->
        result[offset] = (result[offset].toInt() xor (1 shl bit)).toByte()
    }
}

private fun ByteArray.readU16(offset: Int): Int {
    require(offset >= 0 && offset <= size - 2)
    return (this[offset].toInt() and 0xff) or ((this[offset + 1].toInt() and 0xff) shl 8)
}

private fun ByteArray.readU32(offset: Int): Long {
    require(offset >= 0 && offset <= size - 4)
    return (this[offset].toLong() and 0xffL) or
        ((this[offset + 1].toLong() and 0xffL) shl 8) or
        ((this[offset + 2].toLong() and 0xffL) shl 16) or
        ((this[offset + 3].toLong() and 0xffL) shl 24)
}

private fun ByteArray.findSignature(signature: ByteArray): Int = findAllSignatures(signature).singleOrNull()
    ?: error("Expected exactly one ZIP signature ${signature.contentToString()}")

private fun ByteArray.findAllSignatures(signature: ByteArray): List<Int> = buildList {
    require(signature.isNotEmpty())
    for (offset in 0..this@findAllSignatures.size - signature.size) {
        if (signature.indices.all { index -> this@findAllSignatures[offset + index] == signature[index] }) {
            add(offset)
        }
    }
}

private fun ByteArray.matchesAt(offset: Int, sequence: ByteArray): Boolean =
    offset >= 0 && offset <= size - sequence.size &&
        sequence.indices.all { index -> this[offset + index] == sequence[index] }

private val TEST_VALID_CLASS_BYTES = byteArrayOf(
    0xca.toByte(), 0xfe.toByte(), 0xba.toByte(), 0xbe.toByte(), 0, 0, 0, 52,
)
private val TEST_ZIP_CENTRAL_SIGNATURE = byteArrayOf(0x50, 0x4b, 0x01, 0x02)
private val TEST_ZIP_EOCD_SIGNATURE = byteArrayOf(0x50, 0x4b, 0x05, 0x06)
private const val TEST_ZIP_LOCAL_HEADER_SIZE = 30
private const val TEST_ZIP_CENTRAL_HEADER_SIZE = 46
private const val TEST_ZIP_CENTRAL_DOS_TIME_OFFSET = 12
private const val TEST_ZIP_EOCD_SIZE = 22
private const val TEST_TRUNCATED_LOCAL_HEADER_SIZE = 16
private const val TEST_TRUNCATED_CENTRAL_HEADER_SIZE = 20
private const val TEST_ZIP_METHOD_DEFLATED = 8
private const val TEST_ZIP64_EXTRA_ID = 0x0001
private const val TEST_MAXIMUM_ENTRIES = 1_024
private const val MUTATION_CASES = 256
private const val MUTATION_SEED = 0x5eed_c0deL
private const val MUTATION_TIMEOUT_MILLIS = 10_000L
