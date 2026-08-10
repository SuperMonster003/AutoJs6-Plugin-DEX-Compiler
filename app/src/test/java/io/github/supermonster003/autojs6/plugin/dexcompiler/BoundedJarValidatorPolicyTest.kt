package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.autojs.plugin.dexcompiler.api.DexCompilerErrorCode
import org.autojs.plugin.dexcompiler.api.DexCompilerFailurePhase
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.util.zip.CRC32
import java.util.zip.Deflater
import java.util.zip.DeflaterOutputStream

class BoundedJarValidatorPolicyTest {

    @Test
    fun storedJarWithDirectoryClassesAndResourceIsMeasured() = withPolicyFixture { root, runtime ->
        val firstClass = POLICY_CLASS_MAGIC + byteArrayOf(0, 0, 0, 52, 1)
        val secondClass = POLICY_CLASS_MAGIC + byteArrayOf(0, 0, 0, 52, 2, 3)
        val resource = "Manifest-Version: 1.0\r\n".toByteArray(StandardCharsets.UTF_8)
        val entries = listOf(
            PolicyZipEntry("org/autojs/example/", byteArrayOf()),
            PolicyZipEntry("org/autojs/example/First.class", firstClass),
            PolicyZipEntry("org/autojs/example/Second.class", secondClass),
            PolicyZipEntry("META-INF/MANIFEST.MF", resource),
        )
        val program = policyJar(entries)
        val destination = root.resolve("stored-program.jar")

        val result = validatePolicyJar(program, destination, runtime)

        assertEquals(program.size.toLong(), result.compressedSizeBytes)
        assertEquals(entries.size, result.archiveEntryCount)
        assertEquals(2, result.classEntryCount)
        assertEquals(entries.sumOf { it.data.size }.toLong(), result.uncompressedSizeBytes)
        assertEquals((firstClass.size + secondClass.size).toLong(), result.totalClassBytes)
        assertArrayEquals(program, destination.readBytes())
    }

    @Test
    fun deflatedDataDescriptorsWithAndWithoutSignatureAreMeasured() = withPolicyFixture { root, runtime ->
        listOf(true, false).forEachIndexed { index, descriptorSignature ->
            val classBytes = POLICY_CLASS_MAGIC + byteArrayOf(0, 0, 0, 52, index.toByte())
            val resource = "descriptor-$descriptorSignature".toByteArray(StandardCharsets.UTF_8)
            val entries = listOf(
                PolicyZipEntry(
                    "org/autojs/example/Descriptor$index.class",
                    classBytes,
                    method = POLICY_METHOD_DEFLATED,
                    descriptorSignature = descriptorSignature,
                ),
                PolicyZipEntry(
                    "assets/descriptor-$index.txt",
                    resource,
                    method = POLICY_METHOD_DEFLATED,
                    descriptorSignature = descriptorSignature,
                ),
            )
            val program = policyJar(entries)

            val result = validatePolicyJar(program, root.resolve("descriptor-$index.jar"), runtime)

            assertEquals("descriptor signature=$descriptorSignature", program.size.toLong(), result.compressedSizeBytes)
            assertEquals("descriptor signature=$descriptorSignature", 2, result.archiveEntryCount)
            assertEquals("descriptor signature=$descriptorSignature", 1, result.classEntryCount)
            assertEquals(
                "descriptor signature=$descriptorSignature",
                (classBytes.size + resource.size).toLong(),
                result.uncompressedSizeBytes,
            )
            assertEquals(
                "descriptor signature=$descriptorSignature",
                classBytes.size.toLong(),
                result.totalClassBytes,
            )
        }
    }

    @Test
    fun unsafeAndNonCanonicalNamesAreRejected() = withPolicyFixture { root, runtime ->
        val cases = listOf(
            "empty" to "",
            "absolute" to "/Program.class",
            "parent traversal" to "../Program.class",
            "backslash" to "org\\Program.class",
            "colon" to "C:Program.class",
            "NUL" to "org/Program\u0000.class",
            "non-NFC" to "org/Cafe\u0301.class",
            "non-canonical directory suffix" to "org/autojs//",
        )

        cases.forEachIndexed { index, (label, name) ->
            val data = if (name.endsWith('/')) byteArrayOf() else POLICY_CLASS_BYTES
            val program = policyJar(listOf(PolicyZipEntry(name, data)))

            assertPolicyFailure(
                label,
                program,
                root.resolve("unsafe-$index.jar"),
                runtime,
                DexCompilerErrorCode.INVALID_ARCHIVE,
            )
        }
    }

    @Test
    fun duplicateCanonicalEntryNamesAreRejected() = withPolicyFixture { root, runtime ->
        val name = "org/autojs/example/Duplicate.class"
        val program = policyJar(
            listOf(
                PolicyZipEntry(name, POLICY_CLASS_BYTES),
                PolicyZipEntry(name, POLICY_CLASS_MAGIC + byteArrayOf(0, 0, 0, 53)),
            ),
        )

        assertPolicyFailure(
            "duplicate entry",
            program,
            root.resolve("duplicate.jar"),
            runtime,
            DexCompilerErrorCode.INVALID_ARCHIVE,
        )
    }

    @Test
    fun archivesWithoutLowercaseClassSuffixAreRejectedAsHavingNoProgramClasses() =
        withPolicyFixture { root, runtime ->
            val cases = listOf(
                "no class" to PolicyZipEntry("assets/program.bin", POLICY_CLASS_BYTES),
                "uppercase CLASS" to PolicyZipEntry("org/autojs/example/Program.CLASS", POLICY_CLASS_BYTES),
            )

            cases.forEachIndexed { index, (label, entry) ->
                assertPolicyFailure(
                    label,
                    policyJar(listOf(entry)),
                    root.resolve("no-class-$index.jar"),
                    runtime,
                    DexCompilerErrorCode.NO_PROGRAM_CLASSES,
                )
            }
        }

    @Test
    fun lowercaseClassWithInvalidMagicIsRejected() = withPolicyFixture { root, runtime ->
        val program = policyJar(
            listOf(PolicyZipEntry("org/autojs/example/Invalid.class", byteArrayOf(0, 1, 2, 3, 4))),
        )

        assertPolicyFailure(
            "invalid class magic",
            program,
            root.resolve("invalid-magic.jar"),
            runtime,
            DexCompilerErrorCode.INVALID_ARCHIVE,
        )
    }

    @Test
    fun directoryEntryContainingDataIsRejected() = withPolicyFixture { root, runtime ->
        val program = policyJar(
            listOf(
                PolicyZipEntry("org/autojs/example/", byteArrayOf(1)),
                PolicyZipEntry("org/autojs/example/Program.class", POLICY_CLASS_BYTES),
            ),
        )

        assertPolicyFailure(
            "directory data",
            program,
            root.resolve("directory-data.jar"),
            runtime,
            DexCompilerErrorCode.INVALID_ARCHIVE,
        )
    }

    private fun validatePolicyJar(
        program: ByteArray,
        destination: File,
        runtime: RuntimeLibrarySet,
    ): ValidatedJar = BoundedJarValidator.copyAndValidate(
        TestData.request(program, runtime),
        ByteArrayInputStream(program),
        destination,
        DexCompilerRuntime.capabilities(runtime).limits,
    )

    private fun assertPolicyFailure(
        label: String,
        program: ByteArray,
        destination: File,
        runtime: RuntimeLibrarySet,
        expectedCode: DexCompilerErrorCode,
    ) {
        val failure = assertThrows("$label should be rejected", DexCompileFailure::class.java) {
            validatePolicyJar(program, destination, runtime)
        }
        assertEquals(label, expectedCode, failure.code)
        assertEquals(label, DexCompilerFailurePhase.INPUT_VALIDATION, failure.phase)
    }

    private fun withPolicyFixture(block: (root: File, runtime: RuntimeLibrarySet) -> Unit) {
        val root = Files.createTempDirectory("dex-jar-policy-test").toFile()
        try {
            val runtimeFile = root.resolve("runtime.jar").apply { writeBytes(byteArrayOf(9)) }
            block(root, RuntimeLibrarySet.fromFiles(listOf(runtimeFile)))
        } finally {
            root.deleteRecursively()
        }
    }
}

private data class PolicyZipEntry(
    val name: String,
    val data: ByteArray,
    val method: Int = POLICY_METHOD_STORED,
    val descriptorSignature: Boolean? = null,
)

private data class EncodedPolicyZipEntry(
    val name: ByteArray,
    val data: ByteArray,
    val compressedData: ByteArray,
    val method: Int,
    val flags: Int,
    val crc32: Long,
    val localHeaderOffset: Int,
)

private fun policyJar(entries: List<PolicyZipEntry>): ByteArray {
    require(entries.isNotEmpty())
    val output = ByteArrayOutputStream()
    val encoded = entries.map { entry ->
        require(entry.method == POLICY_METHOD_STORED || entry.method == POLICY_METHOD_DEFLATED)
        require(entry.descriptorSignature == null || entry.method == POLICY_METHOD_DEFLATED)
        val name = entry.name.toByteArray(StandardCharsets.UTF_8)
        val compressed = when (entry.method) {
            POLICY_METHOD_STORED -> entry.data
            else -> deflatePolicyBytes(entry.data)
        }
        val crc32 = CRC32().apply { update(entry.data) }.value
        val flags = POLICY_FLAG_UTF8 or if (entry.descriptorSignature != null) POLICY_FLAG_DATA_DESCRIPTOR else 0
        val localHeaderOffset = output.size()

        output.writePolicyU32(POLICY_LOCAL_SIGNATURE)
        output.writePolicyU16(POLICY_VERSION_NEEDED)
        output.writePolicyU16(flags)
        output.writePolicyU16(entry.method)
        output.writePolicyU16(0)
        output.writePolicyU16(0)
        output.writePolicyU32(if (entry.descriptorSignature == null) crc32 else 0)
        output.writePolicyU32(if (entry.descriptorSignature == null) compressed.size.toLong() else 0)
        output.writePolicyU32(if (entry.descriptorSignature == null) entry.data.size.toLong() else 0)
        output.writePolicyU16(name.size)
        output.writePolicyU16(0)
        output.write(name)
        output.write(compressed)
        if (entry.descriptorSignature != null) {
            if (entry.descriptorSignature) output.writePolicyU32(POLICY_DATA_DESCRIPTOR_SIGNATURE)
            output.writePolicyU32(crc32)
            output.writePolicyU32(compressed.size.toLong())
            output.writePolicyU32(entry.data.size.toLong())
        }

        EncodedPolicyZipEntry(
            name = name,
            data = entry.data,
            compressedData = compressed,
            method = entry.method,
            flags = flags,
            crc32 = crc32,
            localHeaderOffset = localHeaderOffset,
        )
    }

    val centralOffset = output.size()
    encoded.forEach { entry ->
        output.writePolicyU32(POLICY_CENTRAL_SIGNATURE)
        output.writePolicyU16(POLICY_VERSION_NEEDED)
        output.writePolicyU16(POLICY_VERSION_NEEDED)
        output.writePolicyU16(entry.flags)
        output.writePolicyU16(entry.method)
        output.writePolicyU16(0)
        output.writePolicyU16(0)
        output.writePolicyU32(entry.crc32)
        output.writePolicyU32(entry.compressedData.size.toLong())
        output.writePolicyU32(entry.data.size.toLong())
        output.writePolicyU16(entry.name.size)
        output.writePolicyU16(0)
        output.writePolicyU16(0)
        output.writePolicyU16(0)
        output.writePolicyU16(0)
        output.writePolicyU32(0)
        output.writePolicyU32(entry.localHeaderOffset.toLong())
        output.write(entry.name)
    }
    val centralSize = output.size() - centralOffset

    output.writePolicyU32(POLICY_EOCD_SIGNATURE)
    output.writePolicyU16(0)
    output.writePolicyU16(0)
    output.writePolicyU16(entries.size)
    output.writePolicyU16(entries.size)
    output.writePolicyU32(centralSize.toLong())
    output.writePolicyU32(centralOffset.toLong())
    output.writePolicyU16(0)
    return output.toByteArray()
}

private fun deflatePolicyBytes(data: ByteArray): ByteArray {
    val deflater = Deflater(Deflater.DEFAULT_COMPRESSION, true)
    return try {
        ByteArrayOutputStream().use { bytes ->
            DeflaterOutputStream(bytes, deflater).use { it.write(data) }
            bytes.toByteArray()
        }
    } finally {
        deflater.end()
    }
}

private fun ByteArrayOutputStream.writePolicyU16(value: Int) {
    require(value in 0..0xffff)
    write(value)
    write(value ushr 8)
}

private fun ByteArrayOutputStream.writePolicyU32(value: Long) {
    require(value in 0..0xffff_ffffL)
    repeat(4) { index -> write((value ushr (index * 8)).toInt()) }
}

private val POLICY_CLASS_MAGIC = byteArrayOf(
    0xca.toByte(), 0xfe.toByte(), 0xba.toByte(), 0xbe.toByte(),
)
private val POLICY_CLASS_BYTES = POLICY_CLASS_MAGIC + byteArrayOf(0, 0, 0, 52)
private const val POLICY_LOCAL_SIGNATURE = 0x04034b50L
private const val POLICY_CENTRAL_SIGNATURE = 0x02014b50L
private const val POLICY_EOCD_SIGNATURE = 0x06054b50L
private const val POLICY_DATA_DESCRIPTOR_SIGNATURE = 0x08074b50L
private const val POLICY_VERSION_NEEDED = 20
private const val POLICY_METHOD_STORED = 0
private const val POLICY_METHOD_DEFLATED = 8
private const val POLICY_FLAG_DATA_DESCRIPTOR = 0x0008
private const val POLICY_FLAG_UTF8 = 0x0800
