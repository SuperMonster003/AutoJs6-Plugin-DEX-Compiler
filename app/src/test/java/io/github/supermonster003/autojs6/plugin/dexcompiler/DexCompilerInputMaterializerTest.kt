package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.autojs.plugin.dexcompiler.api.DexCompileRequest
import org.autojs.plugin.dexcompiler.api.DexCompilerCapabilities
import org.autojs.plugin.dexcompiler.api.DexCompilerClasspathBundleCapability
import org.autojs.plugin.dexcompiler.api.DexCompilerContract
import org.autojs.plugin.dexcompiler.api.DexCompilerErrorCode
import org.autojs.plugin.dexcompiler.api.DexCompilerFailurePhase
import org.autojs.plugin.dexcompiler.api.DexCompilerInputBundleCodec
import org.autojs.plugin.dexcompiler.api.DexCompilerInputBundleSource
import org.autojs.plugin.dexcompiler.api.DexCompilerInputIdentity
import org.autojs.plugin.dexcompiler.api.DexCompilerInputLayout
import org.autojs.plugin.dexcompiler.api.DexCompilerInputRole
import org.autojs.plugin.dexcompiler.api.DexCompilerInputSetFingerprint
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.nio.file.Files

class DexCompilerInputMaterializerTest {
    @Test
    fun v11BundleMaterializesProgramAndOrderedClasspath() = withFixture { _, runtime, workspace ->
        val program = TestData.programJar("example/Program.class")
        val classpath = listOf(
            TestData.programJar("example/FirstDependency.class"),
            TestData.programJar("example/SecondDependency.class"),
        )
        val fixture = bundleFixture(program, classpath, runtime)
        val capabilities = DexCompilerRuntime.capabilities(runtime)

        val materialized = DexCompilerInputMaterializer.materialize(
            request = fixture.request,
            input = ByteArrayInputStream(fixture.bytes),
            workspace = workspace,
            capabilities = capabilities,
        )

        assertArrayEquals(program, materialized.programJar.readBytes())
        assertEquals(2, materialized.classpathJars.size)
        assertArrayEquals(classpath[0], materialized.classpathJars[0].readBytes())
        assertArrayEquals(classpath[1], materialized.classpathJars[1].readBytes())
        assertFalse(capabilities.acceptsExternalClasspath)
        assertNotNull(capabilities.classpathBundle)
    }

    @Test
    fun v11BundleDigestMustMatchTheRequest() = withFixture { _, runtime, workspace ->
        val fixture = bundleFixture(
            TestData.programJar("example/Program.class"),
            listOf(TestData.programJar("example/Dependency.class")),
            runtime,
        )
        val mismatchedRequest = fixture.request.copy(
            inputBundleSha256 = DexHashes.sha256(byteArrayOf(1, 2, 3)),
        )

        val failure = assertThrows(DexCompileFailure::class.java) {
            DexCompilerInputMaterializer.materialize(
                request = mismatchedRequest,
                input = ByteArrayInputStream(fixture.bytes),
                workspace = workspace,
                capabilities = DexCompilerRuntime.capabilities(runtime),
            )
        }

        assertEquals(DexCompilerErrorCode.INVALID_REQUEST, failure.code)
        assertEquals(DexCompilerFailurePhase.INPUT_VALIDATION, failure.phase)
    }

    @Test
    fun v10RawProgramPathRemainsUnchanged() = withFixture { _, runtime, workspace ->
        val program = TestData.programJar()
        val request = TestData.request(program, runtime)

        val materialized = DexCompilerInputMaterializer.materialize(
            request = request,
            input = ByteArrayInputStream(program),
            workspace = workspace,
            capabilities = DexCompilerRuntime.capabilities(runtime),
        )

        assertArrayEquals(program, materialized.programJar.readBytes())
        assertEquals(emptyList<java.io.File>(), materialized.classpathJars)
    }

    @Test
    fun v11AggregateArchiveEntryBudgetIsEnforced() = withFixture { _, runtime, workspace ->
        val fixture = bundleFixture(
            TestData.programJar("example/Program.class"),
            listOf(TestData.programJar("example/Dependency.class")),
            runtime,
        )
        val baseCapabilities = DexCompilerRuntime.capabilities(runtime)
        val baseBundle = requireNotNull(baseCapabilities.classpathBundle)
        val constrainedCapabilities = baseCapabilities.withClasspathBundle(
            baseBundle.copy(
                limits = baseBundle.limits.copy(maxTotalInputArchiveEntries = 1),
            ),
        )

        val failure = assertThrows(DexCompileFailure::class.java) {
            DexCompilerInputMaterializer.materialize(
                request = fixture.request,
                input = ByteArrayInputStream(fixture.bytes),
                workspace = workspace,
                capabilities = constrainedCapabilities,
            )
        }

        assertEquals(DexCompilerErrorCode.INPUT_TOO_LARGE, failure.code)
        assertEquals(DexCompilerFailurePhase.INPUT_VALIDATION, failure.phase)
        assertFalse(workspace.artifactZip.exists())
    }

    private fun bundleFixture(
        program: ByteArray,
        classpath: List<ByteArray>,
        runtime: RuntimeLibrarySet,
    ): BundleFixture {
        val identities = buildList {
            add(identity(DexCompilerInputRole.PROGRAM, 0, program))
            classpath.forEachIndexed { index, bytes ->
                add(identity(DexCompilerInputRole.CLASSPATH, index, bytes))
            }
        }
        val bytes = ByteArrayOutputStream()
        val summary = DexCompilerInputBundleCodec.write(
            output = bytes,
            sources = identities.zip(listOf(program) + classpath).map { (identity, payload) ->
                DexCompilerInputBundleSource(identity) { ByteArrayInputStream(payload) }
            },
        )
        val request = TestData.request(program, runtime).copy(
            protocolVersion = DexCompilerContract.PROTOCOL_V1_1,
            inputLayout = DexCompilerInputLayout.PROGRAM_AND_ORDERED_CLASSPATH_BUNDLE_V1,
            inputIdentities = identities,
            inputSetFingerprint = DexCompilerInputSetFingerprint.compute(identities),
            inputBundleSizeBytes = summary.sizeBytes,
            inputBundleSha256 = summary.contentSha256,
        )
        return BundleFixture(request, bytes.toByteArray())
    }

    private fun identity(
        role: DexCompilerInputRole,
        ordinal: Int,
        payload: ByteArray,
    ) = DexCompilerInputIdentity(role, ordinal, payload.size.toLong(), DexHashes.sha256(payload))

    private fun withFixture(
        block: (java.io.File, RuntimeLibrarySet, PrivateSessionWorkspace) -> Unit,
    ) {
        val root = Files.createTempDirectory("dex-input-materializer-test").toFile()
        try {
            val runtimeFile = root.resolve("runtime.jar").apply { writeBytes(byteArrayOf(9)) }
            val runtime = RuntimeLibrarySet.fromFiles(listOf(runtimeFile))
            PrivateSessionWorkspace.createUnder(root.resolve("sessions")).use { workspace ->
                block(root, runtime, workspace)
            }
        } finally {
            root.deleteRecursively()
        }
    }

    private data class BundleFixture(
        val request: DexCompileRequest,
        val bytes: ByteArray,
    )

    private fun DexCompilerCapabilities.withClasspathBundle(
        capability: DexCompilerClasspathBundleCapability,
    ) = DexCompilerCapabilities(
        compilerFamily = compilerFamily,
        compilerVersion = compilerVersion,
        inputFormats = inputFormats,
        outputFormats = outputFormats,
        modes = modes,
        minApi = minApi,
        maxApi = maxApi,
        supportsMultiDex = supportsMultiDex,
        determinismClaim = determinismClaim,
        runtimeLibraryModel = runtimeLibraryModel,
        acceptsExternalClasspath = acceptsExternalClasspath,
        supportsDesugaredLibraryConfiguration = supportsDesugaredLibraryConfiguration,
        limits = limits,
        runtimeLibraryIdentities = runtimeLibraryIdentities,
        runtimeLibraryFingerprint = runtimeLibraryFingerprint,
        classpathBundle = capability,
    )
}
