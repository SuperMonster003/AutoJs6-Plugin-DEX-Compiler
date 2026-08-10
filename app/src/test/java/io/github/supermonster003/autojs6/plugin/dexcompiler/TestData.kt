package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.autojs.plugin.dexcompiler.api.DexCompileRequest
import org.autojs.plugin.dexcompiler.api.DexCompilerContract
import org.autojs.plugin.dexcompiler.api.DexCompilerInputFormat
import org.autojs.plugin.dexcompiler.api.DexCompilerMode
import org.autojs.plugin.dexcompiler.api.DexCompilerOutputFormat
import org.autojs.plugin.dexcompiler.api.DexRequestId
import org.autojs.plugin.dexcompiler.api.DexRuntimeLibraryModel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

internal object TestData {
    fun programJar(
        entryName: String = "org/autojs/test/Program.class",
        classBytes: ByteArray = byteArrayOf(
            0xca.toByte(), 0xfe.toByte(), 0xba.toByte(), 0xbe.toByte(), 0, 0, 0, 52,
        ),
        archiveComment: String? = null,
        entryExtra: ByteArray = byteArrayOf(),
    ): ByteArray = storedJar(
        entries = listOf(entryName to classBytes),
        archiveComment = archiveComment,
        entryExtra = entryExtra,
    )

    fun storedJar(
        entries: List<Pair<String, ByteArray>>,
        archiveComment: String? = null,
        entryExtra: ByteArray = byteArrayOf(),
    ): ByteArray = ByteArrayOutputStream().use { bytes ->
        ZipOutputStream(bytes).use { zip ->
            archiveComment?.let(zip::setComment)
            entries.forEach { (entryName, entryBytes) ->
                val crc = CRC32().apply { update(entryBytes) }
                zip.putNextEntry(ZipEntry(entryName).apply {
                    method = ZipEntry.STORED
                    size = entryBytes.size.toLong()
                    compressedSize = entryBytes.size.toLong()
                    this.crc = crc.value
                    time = DOS_EPOCH_MILLIS
                    extra = entryExtra
                })
                zip.write(entryBytes)
                zip.closeEntry()
            }
        }
        bytes.toByteArray()
    }

    fun programJarWithDataDescriptor(
        entryName: String = "org/autojs/test/Program.class",
        classBytes: ByteArray = byteArrayOf(
            0xca.toByte(), 0xfe.toByte(), 0xba.toByte(), 0xbe.toByte(), 0, 0, 0, 52,
        ),
    ): ByteArray = ByteArrayOutputStream().use { bytes ->
        ZipOutputStream(bytes).use { zip ->
            zip.putNextEntry(ZipEntry(entryName).apply {
                method = ZipEntry.DEFLATED
                time = DOS_EPOCH_MILLIS
                extra = byteArrayOf()
            })
            zip.write(classBytes)
            zip.closeEntry()
        }
        bytes.toByteArray()
    }

    fun request(program: ByteArray, runtimeLibraries: RuntimeLibrarySet): DexCompileRequest = DexCompileRequest(
        requestId = DexRequestId.fromUuid(UUID.fromString("00000000-0000-0000-0000-000000000001")),
        protocolVersion = DexCompilerRuntime.protocolVersion,
        inputFormat = DexCompilerInputFormat.JAR,
        outputFormat = DexCompilerOutputFormat.DEX_ZIP,
        mode = DexCompilerMode.RELEASE,
        minApi = 24,
        programSizeBytes = program.size.toLong(),
        programSha256 = DexHashes.sha256(program),
        maxOutputBytes = 16L * 1024L * 1024L,
        runtimeLibraryModel = DexRuntimeLibraryModel.DEVICE_RUNTIME_BOOTCLASSPATH_V1,
        expectedRuntimeLibraryFingerprint = runtimeLibraries.fingerprint,
        canonicalizationPolicyVersion = DexCompilerContract.CANONICALIZATION_POLICY_VERSION,
        diagnosticByteLimit = DexCompilerContract.MAX_DIAGNOSTIC_BYTES,
        timeoutMillis = DexCompilerContract.DEFAULT_TIMEOUT_MILLIS,
    )

    fun writeStoredJar(destination: File, entryName: String, bytes: ByteArray) {
        ZipOutputStream(destination.outputStream().buffered()).use { zip ->
            val crc = CRC32().apply { update(bytes) }
            zip.putNextEntry(ZipEntry(entryName).apply {
                method = ZipEntry.STORED
                size = bytes.size.toLong()
                compressedSize = bytes.size.toLong()
                this.crc = crc.value
                time = DOS_EPOCH_MILLIS
                extra = byteArrayOf()
            })
            zip.write(bytes)
            zip.closeEntry()
        }
    }

    private const val DOS_EPOCH_MILLIS = 315_532_800_000L
}
