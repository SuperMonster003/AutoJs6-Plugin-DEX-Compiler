package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.autojs.plugin.dexcompiler.api.DexCompilerErrorCode
import org.autojs.plugin.dexcompiler.api.DexCompilerFailurePhase
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.channels.FileChannel

/**
 * Validates the ZIP records that [java.util.zip.ZipInputStream] deliberately does not require.
 *
 * JAR input must have one canonical, single-disk ZIP framing: local entries start at byte zero,
 * central entries describe those local entries in the same order, and an uncommented EOCD ends the
 * input exactly. ZIP64, encryption, record gaps, comments, and trailing bytes are rejected.
 *
 * Records are read by file offset so validation memory is independent of the archive size. The
 * central directory is consumed in order and only the preceding entry is retained while its local
 * record is checked against the next local-header offset.
 */
internal object StrictJarZipFraming {

    fun validate(file: File, maximumEntries: Int): Int {
        require(maximumEntries > 0)
        return try {
            RandomAccessFile(file, "r").use { archive ->
                validate(ArchiveReader(archive.channel), maximumEntries)
            }
        } catch (error: DexCompileFailure) {
            throw error
        } catch (error: IOException) {
            throw DexCompileFailure(
                DexCompilerErrorCode.INVALID_ARCHIVE,
                DexCompilerFailurePhase.INPUT_VALIDATION,
                "Program JAR could not be read for framing validation",
                error,
            )
        }
    }

    private fun validate(reader: ArchiveReader, maximumEntries: Int): Int {
        if (reader.size < ZIP_EOCD_SIZE) invalidArchive("JAR end-of-central-directory record is missing")

        val eocdOffset = reader.size - ZIP_EOCD_SIZE
        val eocd = reader.readBytes(eocdOffset, ZIP_EOCD_SIZE, "JAR end-of-central-directory record")
        if (eocd.leInt(0) != ZIP_EOCD_SIGNATURE) {
            invalidArchive("JAR end-of-central-directory record is missing or has a comment")
        }
        if (eocd.leU16(4) != 0 || eocd.leU16(6) != 0 || eocd.leU16(20) != 0) {
            invalidArchive("Multi-disk, ZIP64, and commented JARs are forbidden")
        }

        val entriesOnDisk = eocd.leU16(8)
        val entryCount = eocd.leU16(10)
        if (entryCount == 0 || entryCount != entriesOnDisk || entryCount > maximumEntries ||
            entryCount == ZIP64_U16_SENTINEL
        ) {
            invalidArchive("JAR entry count is invalid or exceeds the provider limit")
        }

        val centralSize = eocd.leU32(12)
        val centralOffset = eocd.leU32(16)
        if (centralSize == ZIP64_U32_SENTINEL || centralOffset == ZIP64_U32_SENTINEL ||
            checkedAdd(centralOffset, centralSize, "central directory") != eocdOffset
        ) {
            invalidArchive("JAR central-directory bounds are inconsistent")
        }

        readCentralEntries(
            reader = reader,
            offset = centralOffset,
            declaredSize = centralSize,
            count = entryCount,
        )
        if (reader.currentSize() != reader.size) {
            invalidArchive("JAR size changed during framing validation")
        }
        return entryCount
    }

    private fun readCentralEntries(
        reader: ArchiveReader,
        offset: Long,
        declaredSize: Long,
        count: Int,
    ) {
        var previousEntry: CentralEntry? = null
        var cursor = offset
        repeat(count) { index ->
            val header = reader.readBytes(cursor, ZIP_CENTRAL_HEADER_SIZE, "central-directory header")
            if (header.leInt(0) != ZIP_CENTRAL_SIGNATURE) {
                invalidArchive("Invalid JAR central-directory signature")
            }

            val flags = header.leU16(8)
            val method = header.leU16(10)
            validateFlagsAndMethod(flags, method)
            val crc32 = header.leU32(16)
            val compressedSize = header.leU32(20)
            val uncompressedSize = header.leU32(24)
            val nameLength = header.leU16(28)
            val extraLength = header.leU16(30)
            val commentLength = header.leU16(32)
            val diskStart = header.leU16(34)
            val localHeaderOffset = header.leU32(42)
            if (compressedSize == ZIP64_U32_SENTINEL || uncompressedSize == ZIP64_U32_SENTINEL ||
                localHeaderOffset == ZIP64_U32_SENTINEL || diskStart != 0
            ) {
                invalidArchive("ZIP64 and multi-disk JAR entries are forbidden")
            }
            if (nameLength == 0 || commentLength != 0) {
                invalidArchive("JAR entry names must be non-empty and entry comments are forbidden")
            }

            val recordSize = checkedAdd(
                ZIP_CENTRAL_HEADER_SIZE.toLong(),
                checkedAdd(
                    nameLength.toLong(),
                    checkedAdd(extraLength.toLong(), commentLength.toLong(), "entry metadata"),
                    "entry metadata",
                ),
                "central-directory entry",
            )
            reader.requireRange(cursor, recordSize, "central-directory entry")
            val nameOffset = checkedAdd(cursor, ZIP_CENTRAL_HEADER_SIZE.toLong(), "central entry name")
            validateExtraFields(
                reader,
                checkedAdd(nameOffset, nameLength.toLong(), "central entry extra fields"),
                extraLength,
            )
            val entry = CentralEntry(
                nameOffset = nameOffset,
                nameLength = nameLength,
                flags = flags,
                method = method,
                crc32 = crc32,
                compressedSize = compressedSize,
                uncompressedSize = uncompressedSize,
                localHeaderOffset = localHeaderOffset,
            )

            if (index == 0 && localHeaderOffset != 0L) {
                invalidArchive("Bytes precede the first local JAR entry")
            }
            previousEntry?.let { previous ->
                if (previous.localHeaderOffset >= localHeaderOffset) {
                    invalidArchive("JAR local entries are duplicated or out of order")
                }
                validateLocalEntry(reader, previous, localHeaderOffset)
            }
            previousEntry = entry
            cursor = checkedAdd(cursor, recordSize, "central-directory cursor")
        }

        val expectedEnd = checkedAdd(offset, declaredSize, "central-directory size")
        if (cursor != expectedEnd) {
            invalidArchive("JAR central-directory entry count does not match its declared size")
        }
        validateLocalEntry(reader, previousEntry ?: invalidArchive("JAR central directory is empty"), offset)
    }

    private fun validateLocalEntry(reader: ArchiveReader, entry: CentralEntry, expectedEnd: Long) {
        val cursor = entry.localHeaderOffset
        val header = reader.readBytes(cursor, ZIP_LOCAL_HEADER_SIZE, "local JAR header")
        if (header.leInt(0) != ZIP_LOCAL_SIGNATURE) invalidArchive("Invalid local JAR header signature")

        val flags = header.leU16(6)
        val method = header.leU16(8)
        if (flags != entry.flags || method != entry.method) {
            invalidArchive("Local and central JAR metadata disagree")
        }
        val localCrc32 = header.leU32(14)
        val localCompressedSize = header.leU32(18)
        val localUncompressedSize = header.leU32(22)
        val nameLength = header.leU16(26)
        val extraLength = header.leU16(28)
        val metadataSize = checkedAdd(
            ZIP_LOCAL_HEADER_SIZE.toLong(),
            checkedAdd(nameLength.toLong(), extraLength.toLong(), "local entry metadata"),
            "local entry metadata",
        )
        reader.requireRange(cursor, metadataSize, "local JAR metadata")
        val nameOffset = checkedAdd(cursor, ZIP_LOCAL_HEADER_SIZE.toLong(), "local entry name")
        if (nameLength != entry.nameLength ||
            !reader.rangesEqual(nameOffset, entry.nameOffset, nameLength, "local and central JAR entry names")
        ) {
            invalidArchive("Local and central JAR entry names disagree")
        }
        validateExtraFields(
            reader,
            checkedAdd(nameOffset, nameLength.toLong(), "local entry extra fields"),
            extraLength,
        )

        val hasDescriptor = flags and ZIP_FLAG_DATA_DESCRIPTOR != 0
        if (!hasDescriptor && (localCrc32 != entry.crc32 || localCompressedSize != entry.compressedSize ||
                localUncompressedSize != entry.uncompressedSize)
        ) {
            invalidArchive("Local and central JAR sizes or CRC disagree")
        }
        if (hasDescriptor && !((localCrc32 == 0L || localCrc32 == entry.crc32) &&
                (localCompressedSize == 0L || localCompressedSize == entry.compressedSize) &&
                (localUncompressedSize == 0L || localUncompressedSize == entry.uncompressedSize))
        ) {
            invalidArchive("Local JAR data-descriptor placeholders are inconsistent")
        }

        val dataOffset = checkedAdd(cursor, metadataSize, "local entry data")
        val dataEnd = checkedAdd(dataOffset, entry.compressedSize, "compressed entry data")
        if (dataEnd > expectedEnd) invalidArchive("Compressed JAR entry data exceeds its local record")
        if (hasDescriptor) {
            validateDataDescriptor(reader, dataEnd, expectedEnd, entry)
        } else if (dataEnd != expectedEnd) {
            invalidArchive("Unaccounted bytes follow a local JAR entry")
        }
    }

    private fun validateDataDescriptor(
        reader: ArchiveReader,
        offset: Long,
        expectedEnd: Long,
        entry: CentralEntry,
    ) {
        val descriptorLength = expectedEnd - offset
        val descriptor = when (descriptorLength) {
            12L -> reader.readBytes(offset, 12, "JAR data descriptor")
            16L -> reader.readBytes(offset, 16, "JAR data descriptor").also {
                if (it.leInt(0) != ZIP_DATA_DESCRIPTOR_SIGNATURE) {
                    invalidArchive("Invalid JAR data-descriptor signature")
                }
            }
            else -> invalidArchive("JAR data descriptor has an invalid size")
        }
        val valuesOffset = if (descriptorLength == 16L) 4 else 0
        if (descriptor.leU32(valuesOffset) != entry.crc32 ||
            descriptor.leU32(valuesOffset + 4) != entry.compressedSize ||
            descriptor.leU32(valuesOffset + 8) != entry.uncompressedSize
        ) {
            invalidArchive("JAR data descriptor disagrees with the central directory")
        }
    }

    private fun validateFlagsAndMethod(flags: Int, method: Int) {
        if (flags and ZIP_ALLOWED_FLAGS.inv() != 0) {
            invalidArchive("Encrypted or unsupported JAR flags are present")
        }
        if (method != ZIP_METHOD_STORED && method != ZIP_METHOD_DEFLATED) {
            invalidArchive("Unsupported JAR compression method $method")
        }
        if (method == ZIP_METHOD_STORED && flags and ZIP_DEFLATE_OPTION_FLAGS != 0) {
            invalidArchive("Deflate option flags are set on a stored JAR entry")
        }
    }

    private fun validateExtraFields(reader: ArchiveReader, offset: Long, length: Int) {
        val fields = reader.readBytes(offset, length, "JAR extra fields")
        var cursor = 0
        while (cursor < fields.size) {
            if (fields.size - cursor < 4) invalidArchive("Malformed JAR extra field")
            val id = fields.leU16(cursor)
            val size = fields.leU16(cursor + 2)
            cursor += 4
            if (size > fields.size - cursor || id == ZIP64_EXTRA_ID) {
                invalidArchive("Malformed or ZIP64 JAR extra field")
            }
            cursor += size
        }
    }

    private data class CentralEntry(
        val nameOffset: Long,
        val nameLength: Int,
        val flags: Int,
        val method: Int,
        val crc32: Long,
        val compressedSize: Long,
        val uncompressedSize: Long,
        val localHeaderOffset: Long,
    )
}

private class ArchiveReader(private val channel: FileChannel) {
    val size: Long = channel.size()

    fun currentSize(): Long = channel.size()

    fun readBytes(offset: Long, length: Int, label: String): ByteArray {
        requireRange(offset, length.toLong(), label)
        return ByteArray(length).also { destination ->
            readInto(offset, destination, length, label)
        }
    }

    fun rangesEqual(leftOffset: Long, rightOffset: Long, length: Int, label: String): Boolean {
        requireRange(leftOffset, length.toLong(), label)
        requireRange(rightOffset, length.toLong(), label)
        var cursor = 0
        while (cursor < length) {
            val chunkSize = minOf(NAME_COMPARISON_BUFFER_SIZE, length - cursor)
            readInto(
                checkedAdd(leftOffset, cursor.toLong(), label),
                leftComparisonBuffer,
                chunkSize,
                label,
            )
            readInto(
                checkedAdd(rightOffset, cursor.toLong(), label),
                rightComparisonBuffer,
                chunkSize,
                label,
            )
            for (index in 0 until chunkSize) {
                if (leftComparisonBuffer[index] != rightComparisonBuffer[index]) return false
            }
            cursor += chunkSize
        }
        return true
    }

    fun requireRange(offset: Long, length: Long, label: String) {
        if (offset < 0L || length < 0L || offset > size || length > size - offset) {
            invalidArchive("$label exceeds the JAR container")
        }
    }

    private fun readInto(offset: Long, destination: ByteArray, length: Int, label: String) {
        require(length <= destination.size)
        val buffer = ByteBuffer.wrap(destination, 0, length)
        var position = offset
        while (buffer.hasRemaining()) {
            val read = channel.read(buffer, position)
            if (read <= 0) invalidArchive("$label could not be read completely")
            position = checkedAdd(position, read.toLong(), label)
        }
    }

    private val leftComparisonBuffer = ByteArray(NAME_COMPARISON_BUFFER_SIZE)
    private val rightComparisonBuffer = ByteArray(NAME_COMPARISON_BUFFER_SIZE)
}

private const val ZIP_LOCAL_SIGNATURE = 0x04034b50
private const val ZIP_CENTRAL_SIGNATURE = 0x02014b50
private const val ZIP_EOCD_SIGNATURE = 0x06054b50
private const val ZIP_DATA_DESCRIPTOR_SIGNATURE = 0x08074b50
private const val ZIP_LOCAL_HEADER_SIZE = 30
private const val ZIP_CENTRAL_HEADER_SIZE = 46
private const val ZIP_EOCD_SIZE = 22
private const val ZIP_METHOD_STORED = 0
private const val ZIP_METHOD_DEFLATED = 8
private const val ZIP_FLAG_DATA_DESCRIPTOR = 0x0008
private const val ZIP_FLAG_UTF8 = 0x0800
private const val ZIP_DEFLATE_OPTION_FLAGS = 0x0006
private const val ZIP_ALLOWED_FLAGS = ZIP_FLAG_DATA_DESCRIPTOR or ZIP_FLAG_UTF8 or ZIP_DEFLATE_OPTION_FLAGS
private const val ZIP64_EXTRA_ID = 0x0001
private const val ZIP64_U16_SENTINEL = 0xffff
private const val ZIP64_U32_SENTINEL = 0xffffffffL
private const val NAME_COMPARISON_BUFFER_SIZE = 8 * 1024

private fun ByteArray.leU16(offset: Int): Int {
    requireRange(offset.toLong(), 2L, "JAR uint16")
    return (this[offset].toInt() and 0xff) or ((this[offset + 1].toInt() and 0xff) shl 8)
}

private fun ByteArray.leU32(offset: Int): Long {
    requireRange(offset.toLong(), 4L, "JAR uint32")
    return (this[offset].toLong() and 0xffL) or
        ((this[offset + 1].toLong() and 0xffL) shl 8) or
        ((this[offset + 2].toLong() and 0xffL) shl 16) or
        ((this[offset + 3].toLong() and 0xffL) shl 24)
}

private fun ByteArray.leInt(offset: Int): Int = leU32(offset).toInt()

private fun ByteArray.requireRange(offset: Long, length: Long, label: String) {
    if (offset < 0L || length < 0L || offset > size.toLong() || length > size.toLong() - offset) {
        invalidArchive("$label exceeds the JAR container")
    }
}

private fun checkedAdd(left: Long, right: Long, label: String): Long {
    if (left < 0L || right < 0L || left > Long.MAX_VALUE - right) invalidArchive("JAR $label overflows")
    return left + right
}

private fun invalidArchive(message: String): Nothing = throw DexCompileFailure(
    DexCompilerErrorCode.INVALID_ARCHIVE,
    DexCompilerFailurePhase.INPUT_VALIDATION,
    message,
)
