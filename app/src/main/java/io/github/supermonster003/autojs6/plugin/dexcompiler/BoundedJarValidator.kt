package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.autojs.plugin.dexcompiler.api.DexCompileRequest
import org.autojs.plugin.dexcompiler.api.DexCompilerErrorCode
import org.autojs.plugin.dexcompiler.api.DexCompilerFailurePhase
import org.autojs.plugin.dexcompiler.api.DexCompilerResourceLimits
import org.autojs.plugin.dexcompiler.api.DexSha256
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.security.MessageDigest
import java.text.Normalizer
import java.util.zip.ZipInputStream

internal data class ValidatedJar(
    val compressedSizeBytes: Long,
    val archiveEntryCount: Int,
    val classEntryCount: Int,
    val uncompressedSizeBytes: Long,
    val totalClassBytes: Long,
)

internal object BoundedJarValidator {
    fun copyAndValidate(
        request: DexCompileRequest,
        input: InputStream,
        destination: File,
        limits: DexCompilerResourceLimits,
    ): ValidatedJar {
        val copied = copyBounded(input, destination, limits.maxCompressedProgramBytes)
        if (copied.sizeBytes != request.programSizeBytes) {
            fail(
                DexCompilerErrorCode.INVALID_REQUEST,
                "Program size mismatch: expected ${request.programSizeBytes}, received ${copied.sizeBytes}",
            )
        }
        if (copied.sha256 != request.programSha256) {
            fail(DexCompilerErrorCode.INVALID_REQUEST, "Program SHA-256 mismatch")
        }
        return validateArchive(destination, limits)
    }

    private fun copyBounded(input: InputStream, destination: File, maximumBytes: Long): CopiedProgram {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0L
        try {
            destination.outputStream().buffered().use { output ->
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    if (read == 0) continue
                    total = checkedAdd(total, read.toLong(), "program size")
                    if (total > maximumBytes) {
                        fail(DexCompilerErrorCode.INPUT_TOO_LARGE, "Program archive exceeds the provider limit")
                    }
                    digest.update(buffer, 0, read)
                    output.write(buffer, 0, read)
                }
            }
        } catch (error: Throwable) {
            destination.delete()
            throw error
        }
        if (total == 0L) {
            destination.delete()
            fail(DexCompilerErrorCode.INVALID_ARCHIVE, "Program archive is empty")
        }
        return CopiedProgram(total, DexSha256.fromBytes(digest.digest()))
    }

    private fun validateArchive(file: File, limits: DexCompilerResourceLimits): ValidatedJar {
        val bytes = try {
            file.readBytes()
        } catch (error: IOException) {
            throw DexCompileFailure(
                DexCompilerErrorCode.INVALID_ARCHIVE,
                DexCompilerFailurePhase.INPUT_VALIDATION,
                "Program JAR could not be read for validation",
                error,
            )
        }
        if (!hasZipSignature(bytes)) {
            fail(DexCompilerErrorCode.INVALID_ARCHIVE, "Program is not a ZIP-compatible JAR")
        }
        val framedEntryCount = StrictJarZipFraming.validate(bytes, limits.maxArchiveEntries)
        val seenNames = HashSet<String>()
        var entryCount = 0
        var classCount = 0
        var uncompressedBytes = 0L
        var totalClassBytes = 0L
        var totalCompressedBytes = 0L

        try {
            ZipInputStream(ByteArrayInputStream(bytes)).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    entryCount++
                    if (entryCount > limits.maxArchiveEntries) {
                        fail(DexCompilerErrorCode.INVALID_ARCHIVE, "JAR contains too many entries")
                    }
                    val canonicalName = canonicalEntryName(entry.name, entry.isDirectory)
                    if (!seenNames.add(canonicalName)) {
                        fail(DexCompilerErrorCode.INVALID_ARCHIVE, "JAR contains a duplicate entry: $canonicalName")
                    }
                    val isClass = !entry.isDirectory && canonicalName.endsWith(".class")
                    val entryContent = readEntry(zip, isClass, limits.maxSingleClassBytes) { count ->
                        uncompressedBytes = checkedAdd(uncompressedBytes, count.toLong(), "uncompressed JAR size")
                        if (uncompressedBytes > limits.maxUncompressedProgramBytes) {
                            fail(DexCompilerErrorCode.INVALID_ARCHIVE, "JAR uncompressed data exceeds the provider limit")
                        }
                    }
                    if (entry.isDirectory && entryContent.sizeBytes != 0L) {
                        fail(DexCompilerErrorCode.INVALID_ARCHIVE, "JAR directory entry contains data: ${entry.name}")
                    }
                    val compressedSize = entry.compressedSize
                    if (compressedSize < 0L) {
                        fail(DexCompilerErrorCode.INVALID_ARCHIVE, "JAR entry has no measurable compressed size")
                    }
                    enforceCompressionRatio(
                        uncompressedBytes = entryContent.sizeBytes,
                        compressedBytes = compressedSize,
                        maximumRatio = MAX_ENTRY_COMPRESSION_RATIO,
                        label = "JAR entry",
                    )
                    totalCompressedBytes = checkedAdd(totalCompressedBytes, compressedSize, "compressed JAR size")
                    if (isClass) {
                        classCount++
                        totalClassBytes = checkedAdd(totalClassBytes, entryContent.sizeBytes, "class data size")
                        if (totalClassBytes > limits.maxTotalClassBytes) {
                            fail(DexCompilerErrorCode.INVALID_ARCHIVE, "JAR class data exceeds the provider limit")
                        }
                        validateClassMagic(entry.name, entryContent.prefix)
                    }
                    zip.closeEntry()
                }
            }
        } catch (error: DexCompileFailure) {
            throw error
        } catch (error: IOException) {
            throw DexCompileFailure(
                DexCompilerErrorCode.INVALID_ARCHIVE,
                DexCompilerFailurePhase.INPUT_VALIDATION,
                "Program JAR is malformed",
                error,
            )
        } catch (error: IllegalArgumentException) {
            throw DexCompileFailure(
                DexCompilerErrorCode.INVALID_ARCHIVE,
                DexCompilerFailurePhase.INPUT_VALIDATION,
                "Program JAR contains malformed metadata",
                error,
            )
        }

        if (entryCount == 0) fail(DexCompilerErrorCode.INVALID_ARCHIVE, "Program JAR contains no entries")
        if (entryCount != framedEntryCount) {
            fail(DexCompilerErrorCode.INVALID_ARCHIVE, "Program JAR local and central entry counts disagree")
        }
        if (classCount == 0) {
            fail(DexCompilerErrorCode.NO_PROGRAM_CLASSES, "Program JAR contains no class files")
        }
        enforceCompressionRatio(
            uncompressedBytes,
            totalCompressedBytes,
            MAX_AGGREGATE_COMPRESSION_RATIO,
            "JAR aggregate",
        )
        enforceCompressionRatio(
            uncompressedBytes,
            bytes.size.toLong(),
            MAX_AGGREGATE_COMPRESSION_RATIO,
            "JAR envelope",
        )
        return ValidatedJar(
            compressedSizeBytes = bytes.size.toLong(),
            archiveEntryCount = entryCount,
            classEntryCount = classCount,
            uncompressedSizeBytes = uncompressedBytes,
            totalClassBytes = totalClassBytes,
        )
    }

    private fun readEntry(
        input: InputStream,
        retainClassPrefix: Boolean,
        maxSingleClassBytes: Long,
        onBytes: (Int) -> Unit,
    ): EntryContent {
        val prefix = ByteArray(CLASS_MAGIC.size)
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var entryBytes = 0L
        var prefixBytes = 0
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            if (read == 0) continue
            if (retainClassPrefix && prefixBytes < prefix.size) {
                val retained = minOf(read, prefix.size - prefixBytes)
                buffer.copyInto(prefix, prefixBytes, 0, retained)
                prefixBytes += retained
            }
            entryBytes = checkedAdd(entryBytes, read.toLong(), "JAR entry size")
            onBytes(read)
            if (retainClassPrefix && entryBytes > maxSingleClassBytes) {
                fail(DexCompilerErrorCode.INVALID_ARCHIVE, "A class entry exceeds the provider limit")
            }
        }
        return EntryContent(entryBytes, prefix.copyOf(prefixBytes))
    }

    private fun canonicalEntryName(name: String, isDirectory: Boolean): String {
        val expectedBody = if (isDirectory) name.removeSuffix("/") else name
        val hasCanonicalDirectorySuffix = !isDirectory || (name.endsWith('/') && !name.endsWith("//"))
        val segments = expectedBody.split('/')
        if (
            name.isEmpty() || name.startsWith('/') || name.contains('\u0000') || name.contains('\\') ||
            name.contains(':') || !hasCanonicalDirectorySuffix ||
            Normalizer.normalize(expectedBody, Normalizer.Form.NFC) != expectedBody ||
            segments.any { it.isEmpty() || it == "." || it == ".." }
        ) {
            fail(DexCompilerErrorCode.INVALID_ARCHIVE, "JAR entry name is unsafe: $name")
        }
        return segments.joinToString("/")
    }

    private fun validateClassMagic(name: String, prefix: ByteArray) {
        if (!prefix.contentEquals(CLASS_MAGIC)) {
            fail(DexCompilerErrorCode.INVALID_ARCHIVE, "Class entry has invalid magic: $name")
        }
    }

    private fun hasZipSignature(bytes: ByteArray): Boolean {
        if (bytes.size < 4) return false
        val signature = (bytes[0].toInt() and 0xff) or
            ((bytes[1].toInt() and 0xff) shl 8) or
            ((bytes[2].toInt() and 0xff) shl 16) or
            ((bytes[3].toInt() and 0xff) shl 24)
        return signature == ZIP_LOCAL_SIGNATURE
    }

    private fun enforceCompressionRatio(
        uncompressedBytes: Long,
        compressedBytes: Long,
        maximumRatio: Long,
        label: String,
    ) {
        val exceedsLimit = when {
            uncompressedBytes == 0L -> false
            compressedBytes <= 0L -> true
            compressedBytes > Long.MAX_VALUE / maximumRatio -> false
            else -> uncompressedBytes > compressedBytes * maximumRatio
        }
        if (exceedsLimit) {
            fail(DexCompilerErrorCode.INVALID_ARCHIVE, "$label compression ratio exceeds the provider limit")
        }
    }

    private fun checkedAdd(left: Long, right: Long, label: String): Long = try {
        Math.addExact(left, right)
    } catch (error: ArithmeticException) {
        throw DexCompileFailure(
            DexCompilerErrorCode.INVALID_ARCHIVE,
            DexCompilerFailurePhase.INPUT_VALIDATION,
            "$label overflows",
            error,
        )
    }

    private fun fail(code: DexCompilerErrorCode, message: String): Nothing = throw DexCompileFailure(
        code,
        DexCompilerFailurePhase.INPUT_VALIDATION,
        message,
    )

    private val CLASS_MAGIC = byteArrayOf(0xca.toByte(), 0xfe.toByte(), 0xba.toByte(), 0xbe.toByte())
    private const val ZIP_LOCAL_SIGNATURE = 0x04034b50
    private const val MAX_ENTRY_COMPRESSION_RATIO = 100L
    private const val MAX_AGGREGATE_COMPRESSION_RATIO = 100L

    private data class CopiedProgram(val sizeBytes: Long, val sha256: DexSha256)
    private data class EntryContent(val sizeBytes: Long, val prefix: ByteArray)
}
