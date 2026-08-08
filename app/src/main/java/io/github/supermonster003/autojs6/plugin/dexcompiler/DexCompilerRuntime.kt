package io.github.supermonster003.autojs6.plugin.dexcompiler

import android.content.Context
import android.os.Build
import org.autojs.plugin.dexcompiler.api.DexCompilerAbiMode
import org.autojs.plugin.dexcompiler.api.DexCompilerCapabilities
import org.autojs.plugin.dexcompiler.api.DexCompilerContract
import org.autojs.plugin.dexcompiler.api.DexCompilerDeterminismClaim
import org.autojs.plugin.dexcompiler.api.DexCompilerFamily
import org.autojs.plugin.dexcompiler.api.DexCompilerInfo
import org.autojs.plugin.dexcompiler.api.DexCompilerInputFormat
import org.autojs.plugin.dexcompiler.api.DexCompilerMode
import org.autojs.plugin.dexcompiler.api.DexCompilerOutputFormat
import org.autojs.plugin.dexcompiler.api.DexCompilerResourceLimits
import org.autojs.plugin.dexcompiler.api.DexProtocolVersion
import org.autojs.plugin.dexcompiler.api.DexRuntimeLibraryModel

internal object DexCompilerRuntime {
    const val HOST_PACKAGE_NAME = "org.autojs.autojs6"
    const val APPLICATION_ID = "io.github.supermonster003.autojs6.plugin.dexcompiler"
    const val PLUGIN_ID = "dex-compiler"
    const val PLUGIN_VARIANT = "d8"
    const val PROVIDER_ID = "autojs6-d8"
    const val COMPILER_VERSION = "8.13.17"
    const val REQUIRED_HOST_VERSION = 5_270L

    val protocolVersion = DexProtocolVersion(
        DexCompilerContract.PROTOCOL_MAJOR,
        DexCompilerContract.PROTOCOL_MINOR,
    )

    private val limits = DexCompilerResourceLimits(
        maxCompressedProgramBytes = 64L * 1024L * 1024L,
        maxArchiveEntries = DexCompilerContract.MAX_ARCHIVE_ENTRIES,
        maxUncompressedProgramBytes = DexCompilerContract.MAX_UNCOMPRESSED_PROGRAM_BYTES,
        maxTotalClassBytes = DexCompilerContract.MAX_TOTAL_CLASS_BYTES,
        maxSingleClassBytes = DexCompilerContract.MAX_SINGLE_CLASS_BYTES,
        maxOutputBytes = 16L * 1024L * 1024L,
        maxDexEntries = DexCompilerContract.MAX_DEX_ENTRIES,
        maxDiagnosticBytes = DexCompilerContract.MAX_DIAGNOSTIC_BYTES,
        maxConcurrentSessions = DexCompilerContract.MAX_CONCURRENT_SESSIONS,
    )

    fun info(context: Context): DexCompilerInfo {
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode.toLong()
        }
        return DexCompilerInfo(
            protocolMin = protocolVersion,
            protocolMax = protocolVersion,
            providerId = PROVIDER_ID,
            providerVersionName = packageInfo.versionName.orEmpty(),
            providerVersionCode = versionCode,
            minHostVersionCode = REQUIRED_HOST_VERSION,
            abiMode = DexCompilerAbiMode.ANY,
        )
    }

    fun capabilities(runtimeLibraries: RuntimeLibrarySet) = DexCompilerCapabilities(
        compilerFamily = DexCompilerFamily.D8,
        compilerVersion = COMPILER_VERSION,
        inputFormats = listOf(DexCompilerInputFormat.JAR),
        outputFormats = listOf(DexCompilerOutputFormat.DEX_ZIP),
        modes = listOf(DexCompilerMode.DEBUG, DexCompilerMode.RELEASE),
        minApi = 24,
        maxApi = 36,
        supportsMultiDex = true,
        determinismClaim = DexCompilerDeterminismClaim.NOT_CLAIMED,
        runtimeLibraryModel = DexRuntimeLibraryModel.DEVICE_RUNTIME_BOOTCLASSPATH_V1,
        acceptsExternalClasspath = false,
        supportsDesugaredLibraryConfiguration = false,
        limits = limits,
        runtimeLibraryIdentities = runtimeLibraries.identities,
        runtimeLibraryFingerprint = runtimeLibraries.fingerprint,
    )
}
