package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.autojs.plugin.dexcompiler.api.DexCompilerErrorCode
import org.autojs.plugin.dexcompiler.api.DexCompilerDiagnostic
import org.autojs.plugin.dexcompiler.api.DexCompilerFailurePhase
import org.autojs.plugin.dexcompiler.api.DexSha256
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.FilterOutputStream
import java.io.IOException
import java.io.OutputStream
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

internal data class DexArtifact(
    val file: File,
    val outputSizeBytes: Long,
    val outputSha256: DexSha256,
    val dexEntryCount: Int,
    val diagnostics: List<DexCompilerDiagnostic> = emptyList(),
)

internal object DexIndexedOutputPackager {
    fun packageOutput(
        d8OutputDirectory: File,
        destination: File,
        maximumOutputBytes: Long,
        maximumDexEntries: Int,
    ): DexArtifact {
        require(maximumOutputBytes > 0L)
        require(maximumDexEntries > 0)
        val children = d8OutputDirectory.listFiles()
            ?: fail(DexCompilerErrorCode.INTERNAL, "D8 output directory could not be listed")
        val indexed = children.map { file ->
            val index = dexIndex(file.name)
                ?: fail(DexCompilerErrorCode.INTERNAL, "D8 produced an unexpected output: ${file.name}")
            if (!file.isFile || file.length() <= 0L) {
                fail(DexCompilerErrorCode.COMPILATION_FAILED, "D8 produced an empty or non-file DEX output")
            }
            index to file
        }.sortedBy(Pair<Int, File>::first)

        if (indexed.isEmpty()) {
            fail(DexCompilerErrorCode.COMPILATION_FAILED, "D8 did not produce any classes*.dex files")
        }
        if (indexed.size > maximumDexEntries) {
            fail(DexCompilerErrorCode.OUTPUT_TOO_LARGE, "D8 produced too many DEX entries")
        }
        indexed.forEachIndexed { zeroBasedIndex, pair ->
            if (pair.first != zeroBasedIndex + 1) {
                fail(DexCompilerErrorCode.INTERNAL, "D8 produced non-contiguous indexed DEX files")
            }
        }

        try {
            val limited = LimitedOutputStream(
                BufferedOutputStream(FileOutputStream(destination)),
                maximumOutputBytes,
            )
            ZipOutputStream(limited).use { zip ->
                indexed.forEach { (_, dexFile) ->
                    val crc = crc32(dexFile)
                    val entry = ZipEntry(dexFile.name).apply {
                        method = ZipEntry.STORED
                        size = dexFile.length()
                        compressedSize = dexFile.length()
                        this.crc = crc
                        time = DOS_EPOCH_MILLIS
                        extra = byteArrayOf()
                    }
                    zip.putNextEntry(entry)
                    dexFile.inputStream().buffered().use { it.copyTo(zip) }
                    zip.closeEntry()
                }
            }
        } catch (error: OutputLimitExceeded) {
            destination.delete()
            throw DexCompileFailure(
                DexCompilerErrorCode.OUTPUT_TOO_LARGE,
                DexCompilerFailurePhase.OUTPUT_PACKAGING,
                "DEX ZIP exceeds the requested output limit",
                error,
            )
        } catch (error: IOException) {
            destination.delete()
            throw DexCompileFailure(
                DexCompilerErrorCode.STORAGE_EXHAUSTED,
                DexCompilerFailurePhase.OUTPUT_PACKAGING,
                "Failed to package the D8 output",
                error,
            )
        }

        val outputSize = destination.length()
        if (outputSize <= 0L || outputSize > maximumOutputBytes) {
            destination.delete()
            fail(DexCompilerErrorCode.OUTPUT_TOO_LARGE, "DEX ZIP is outside the requested output limit")
        }
        return DexArtifact(
            file = destination,
            outputSizeBytes = outputSize,
            outputSha256 = DexHashes.sha256(destination),
            dexEntryCount = indexed.size,
        )
    }

    internal fun dexIndex(name: String): Int? {
        if (name == "classes.dex") return 1
        if (!name.startsWith("classes") || !name.endsWith(".dex")) return null
        val digits = name.substring(7, name.length - 4)
        if (digits.isEmpty() || digits.startsWith('0') || digits.any { it !in '0'..'9' }) return null
        return digits.toIntOrNull()?.takeIf { it >= 2 }
    }

    private fun crc32(file: File): Long {
        val crc = CRC32()
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                if (read > 0) crc.update(buffer, 0, read)
            }
        }
        return crc.value
    }

    private fun fail(code: DexCompilerErrorCode, message: String): Nothing = throw DexCompileFailure(
        code,
        DexCompilerFailurePhase.OUTPUT_PACKAGING,
        message,
    )

    private class LimitedOutputStream(
        delegate: OutputStream,
        private val maximumBytes: Long,
    ) : FilterOutputStream(delegate) {
        private var written = 0L

        override fun write(value: Int) {
            claim(1)
            out.write(value)
        }

        override fun write(bytes: ByteArray, offset: Int, length: Int) {
            claim(length)
            out.write(bytes, offset, length)
        }

        private fun claim(count: Int) {
            if (count < 0 || written > maximumBytes - count.toLong()) throw OutputLimitExceeded()
            written += count
        }
    }

    private class OutputLimitExceeded : IOException()

    private const val DOS_EPOCH_MILLIS = 315_532_800_000L
}
