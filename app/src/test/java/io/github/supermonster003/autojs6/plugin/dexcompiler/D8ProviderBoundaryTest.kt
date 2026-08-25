package io.github.supermonster003.autojs6.plugin.dexcompiler

import com.android.tools.r8.CompilationMode
import org.autojs.plugin.dexcompiler.api.DexCompilerContract
import org.autojs.plugin.dexcompiler.api.DexCompilerDeterminismClaim
import org.autojs.plugin.dexcompiler.api.DexCompilerFamily
import org.autojs.plugin.dexcompiler.api.DexCompilerInputFormat
import org.autojs.plugin.dexcompiler.api.DexCompilerInputRole
import org.autojs.plugin.dexcompiler.api.DexCompilerMode
import org.autojs.plugin.dexcompiler.api.DexCompilerOutputFormat
import org.autojs.plugin.dexcompiler.api.DexCompilerValidation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class D8ProviderBoundaryTest {
    @Test
    fun exactProviderIdentityRemainsD8Only() {
        assertEquals("io.github.supermonster003.autojs6.plugin.dexcompiler", DexCompilerRuntime.APPLICATION_ID)
        assertEquals("dex-compiler", DexCompilerRuntime.PLUGIN_ID)
        assertEquals("d8", DexCompilerRuntime.PLUGIN_VARIANT)
        assertEquals("autojs6-d8", DexCompilerRuntime.PROVIDER_ID)
        assertEquals("dex-compiler", DexCompilerContract.ENGINE_ID)
        assertEquals("org.autojs.plugin.DEX_COMPILER", DexCompilerContract.SERVICE_ACTION)
        assertEquals("d8", D8_PLUGIN_FAMILY_ID)
    }

    @Test
    fun capabilitiesRemainBoundedJarToDexWithNoDeterminismClaim() {
        withRuntimeLibraries { runtimeLibraries ->
            val capabilities = DexCompilerRuntime.capabilities(runtimeLibraries)

            DexCompilerValidation.validateCapabilities(capabilities)
            assertEquals(DexCompilerFamily.D8, capabilities.compilerFamily)
            assertEquals(DexCompilerRuntime.COMPILER_VERSION, capabilities.compilerVersion)
            assertEquals(listOf(DexCompilerInputFormat.JAR), capabilities.inputFormats)
            assertEquals(listOf(DexCompilerOutputFormat.DEX_ZIP), capabilities.outputFormats)
            assertEquals(listOf(DexCompilerMode.DEBUG, DexCompilerMode.RELEASE), capabilities.modes)
            assertEquals(24, capabilities.minApi)
            assertEquals(36, capabilities.maxApi)
            assertTrue(capabilities.supportsMultiDex)
            assertFalse(capabilities.acceptsExternalClasspath)
            assertFalse(capabilities.supportsDesugaredLibraryConfiguration)
            assertEquals(DexCompilerDeterminismClaim.NOT_CLAIMED, capabilities.determinismClaim)
        }
    }

    @Test
    fun protocolCompilerFamilyEnumStillContainsOnlyD8() {
        assertEquals(listOf(DexCompilerFamily.D8), enumValues<DexCompilerFamily>().toList())
    }

    @Test
    fun wirePayloadCannotCarrySourceOrPackagedApplicationArtifacts() {
        assertEquals(listOf(DexCompilerInputFormat.JAR), enumValues<DexCompilerInputFormat>().toList())
        assertEquals(
            listOf(DexCompilerInputRole.PROGRAM, DexCompilerInputRole.CLASSPATH),
            enumValues<DexCompilerInputRole>().toList(),
        )
        assertEquals(listOf(DexCompilerOutputFormat.DEX_ZIP), enumValues<DexCompilerOutputFormat>().toList())
    }

    @Test
    fun wireModesMapExhaustivelyToD8CommandAndCliModes() {
        assertEquals(listOf(DexCompilerMode.DEBUG, DexCompilerMode.RELEASE), enumValues<DexCompilerMode>().toList())

        assertEquals(
            D8ExecutionMode(CompilationMode.DEBUG, "--debug"),
            DexCompilerMode.DEBUG.toD8ExecutionMode(),
        )
        assertEquals(
            D8ExecutionMode(CompilationMode.RELEASE, "--release"),
            DexCompilerMode.RELEASE.toD8ExecutionMode(),
        )
    }

    private fun withRuntimeLibraries(block: (RuntimeLibrarySet) -> Unit) {
        val runtimeLibrary = Files.createTempFile("d8-provider-boundary-runtime", ".jar").toFile()
        try {
            runtimeLibrary.writeBytes(byteArrayOf(0x01))
            block(RuntimeLibrarySet.fromFiles(listOf(runtimeLibrary)))
        } finally {
            runtimeLibrary.delete()
        }
    }
}
