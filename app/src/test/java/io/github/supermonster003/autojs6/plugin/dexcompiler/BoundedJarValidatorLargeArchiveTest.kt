package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.autojs.plugin.dexcompiler.api.DexCompileRequest
import org.autojs.plugin.dexcompiler.api.DexCompilerContract
import org.autojs.plugin.dexcompiler.api.DexCompilerInputFormat
import org.autojs.plugin.dexcompiler.api.DexCompilerMode
import org.autojs.plugin.dexcompiler.api.DexCompilerOutputFormat
import org.autojs.plugin.dexcompiler.api.DexRequestId
import org.autojs.plugin.dexcompiler.api.DexRuntimeLibraryModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.util.UUID
import java.util.zip.Deflater
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class BoundedJarValidatorLargeArchiveTest {
    @Test(timeout = TEST_TIMEOUT_MILLIS)
    fun nearInputLimitArchiveIsValidatedWithoutAnArchiveSizedHeapBuffer() {
        val root = Files.createTempDirectory("dex-jar-large-streaming-test").toFile()
        try {
            val runtimeFile = root.resolve("runtime.jar").apply { writeBytes(byteArrayOf(9)) }
            val runtime = RuntimeLibrarySet.fromFiles(listOf(runtimeFile))
            val limits = DexCompilerRuntime.capabilities(runtime).limits
            val source = root.resolve("source.jar")
            writeNearLimitJar(source)

            assertTrue(
                "fixture must remain close to the provider input limit",
                source.length() >= limits.maxCompressedProgramBytes - TWO_MEBIBYTES,
            )
            assertTrue(
                "fixture must not exceed the provider input limit",
                source.length() <= limits.maxCompressedProgramBytes,
            )
            val maximumHeapBytes = Runtime.getRuntime().maxMemory()
            println(
                "R0_LARGE_ARCHIVE_EVIDENCE sourceBytes=${source.length()} " +
                    "providerLimitBytes=${limits.maxCompressedProgramBytes} maxHeapBytes=$maximumHeapBytes",
            )
            System.getProperty(CONSTRAINED_HEAP_PROPERTY)?.let { configuredHeap ->
                assertTrue(
                    "constrained run must use a small test heap ($configuredHeap configured)",
                    maximumHeapBytes <= MAX_CONSTRAINED_HEAP_BYTES,
                )
                assertTrue(
                    "test JVM max heap must be smaller than the archive itself",
                    maximumHeapBytes < source.length(),
                )
            }

            val destination = root.resolve("validated.jar")
            val result = source.inputStream().buffered().use { input ->
                BoundedJarValidator.copyAndValidate(
                    request(source, runtime),
                    input,
                    destination,
                    limits,
                )
            }

            assertEquals(source.length(), result.compressedSizeBytes)
            assertEquals(2, result.archiveEntryCount)
            assertEquals(1, result.classEntryCount)
            assertEquals(PAYLOAD_SIZE_BYTES + VALID_CLASS_BYTES.size, result.uncompressedSizeBytes)
            assertEquals(VALID_CLASS_BYTES.size.toLong(), result.totalClassBytes)
            assertEquals(DexHashes.sha256(source), DexHashes.sha256(destination))
        } finally {
            root.deleteRecursively()
        }
    }

    private fun request(program: File, runtime: RuntimeLibrarySet) = DexCompileRequest(
        requestId = DexRequestId.fromUuid(UUID.fromString("00000000-0000-0000-0000-000000000002")),
        protocolVersion = DexCompilerRuntime.protocolVersion,
        inputFormat = DexCompilerInputFormat.JAR,
        outputFormat = DexCompilerOutputFormat.DEX_ZIP,
        mode = DexCompilerMode.RELEASE,
        minApi = 24,
        programSizeBytes = program.length(),
        programSha256 = DexHashes.sha256(program),
        maxOutputBytes = 16L * 1024L * 1024L,
        runtimeLibraryModel = DexRuntimeLibraryModel.DEVICE_RUNTIME_BOOTCLASSPATH_V1,
        expectedRuntimeLibraryFingerprint = runtime.fingerprint,
        canonicalizationPolicyVersion = DexCompilerContract.CANONICALIZATION_POLICY_VERSION,
        diagnosticByteLimit = DexCompilerContract.MAX_DIAGNOSTIC_BYTES,
        timeoutMillis = DexCompilerContract.DEFAULT_TIMEOUT_MILLIS,
    )

    private fun writeNearLimitJar(destination: File) {
        ZipOutputStream(destination.outputStream().buffered()).use { zip ->
            zip.setLevel(Deflater.NO_COMPRESSION)
            zip.putNextEntry(ZipEntry("payload.bin").apply {
                method = ZipEntry.DEFLATED
                time = DOS_EPOCH_MILLIS
                extra = byteArrayOf()
            })
            val buffer = ByteArray(STREAM_BUFFER_BYTES) { index -> (index * 31 + 17).toByte() }
            var remaining = PAYLOAD_SIZE_BYTES
            while (remaining > 0L) {
                val count = minOf(buffer.size.toLong(), remaining).toInt()
                zip.write(buffer, 0, count)
                remaining -= count
            }
            zip.closeEntry()

            zip.putNextEntry(ZipEntry("org/autojs/test/LargeProgram.class").apply {
                method = ZipEntry.DEFLATED
                time = DOS_EPOCH_MILLIS
                extra = byteArrayOf()
            })
            zip.write(VALID_CLASS_BYTES)
            zip.closeEntry()
        }
    }

    private companion object {
        const val TEST_TIMEOUT_MILLIS = 120_000L
        const val STREAM_BUFFER_BYTES = 64 * 1024
        const val TWO_MEBIBYTES = 2L * 1024L * 1024L
        const val PAYLOAD_SIZE_BYTES = 63L * 1024L * 1024L + 512L * 1024L
        const val MAX_CONSTRAINED_HEAP_BYTES = 60L * 1024L * 1024L
        const val CONSTRAINED_HEAP_PROPERTY = "r0.test.maxHeap"
        const val DOS_EPOCH_MILLIS = 315_532_800_000L

        val VALID_CLASS_BYTES = byteArrayOf(
            0xca.toByte(), 0xfe.toByte(), 0xba.toByte(), 0xbe.toByte(), 0, 0, 0, 52,
        )
    }
}
