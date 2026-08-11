package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.autojs.plugin.dexcompiler.api.DexCompileRequest
import org.autojs.plugin.dexcompiler.api.DexCompilerCapabilities
import org.autojs.plugin.dexcompiler.api.DexCompilerClasspathBundleLimits
import org.autojs.plugin.dexcompiler.api.DexCompilerContract
import org.autojs.plugin.dexcompiler.api.DexCompilerErrorCode
import org.autojs.plugin.dexcompiler.api.DexCompilerFailurePhase
import org.autojs.plugin.dexcompiler.api.DexCompilerInputBundleError
import org.autojs.plugin.dexcompiler.api.DexCompilerInputBundleException
import org.autojs.plugin.dexcompiler.api.DexCompilerInputBundleLimits
import org.autojs.plugin.dexcompiler.api.DexCompilerInputBundleCodec
import org.autojs.plugin.dexcompiler.api.DexCompilerInputRole
import java.io.File
import java.io.InputStream

internal data class MaterializedDexInputs(
    val programJar: File,
    val classpathJars: List<File>,
)

/** Materializes either the V1.0 raw JAR or the V1.1 canonical bundle into one private workspace. */
internal object DexCompilerInputMaterializer {
    fun materialize(
        request: DexCompileRequest,
        input: InputStream,
        workspace: PrivateSessionWorkspace,
        capabilities: DexCompilerCapabilities,
        ensureActive: () -> Unit = {},
    ): MaterializedDexInputs = when (request.protocolVersion) {
        DexCompilerContract.PROTOCOL_V1_0 -> materializeRaw(
            request,
            input,
            workspace,
            capabilities,
            ensureActive,
        )
        DexCompilerContract.PROTOCOL_V1_1 -> materializeBundle(
            request,
            input,
            workspace,
            capabilities,
            ensureActive,
        )
        else -> throw DexCompileFailure(
            DexCompilerErrorCode.UNSUPPORTED_PROTOCOL,
            DexCompilerFailurePhase.NEGOTIATION,
            "Compile request protocol version is unsupported",
        )
    }

    private fun materializeRaw(
        request: DexCompileRequest,
        input: InputStream,
        workspace: PrivateSessionWorkspace,
        capabilities: DexCompilerCapabilities,
        ensureActive: () -> Unit,
    ): MaterializedDexInputs {
        ensureActive()
        BoundedJarValidator.copyAndValidate(
            request = request,
            input = input,
            destination = workspace.programJar,
            limits = capabilities.limits,
        )
        ensureActive()
        return MaterializedDexInputs(workspace.programJar, emptyList())
    }

    private fun materializeBundle(
        request: DexCompileRequest,
        input: InputStream,
        workspace: PrivateSessionWorkspace,
        capabilities: DexCompilerCapabilities,
        ensureActive: () -> Unit,
    ): MaterializedDexInputs {
        val capability = capabilities.classpathBundle ?: throw DexCompileFailure(
            DexCompilerErrorCode.UNSUPPORTED_CAPABILITY,
            DexCompilerFailurePhase.NEGOTIATION,
            "Provider does not advertise ordered classpath bundles",
        )
        val classpathJars = ArrayList<File>()
        val aggregate = AggregateInputBudget(capability.limits)
        var entryIndex = 0
        val summary = try {
            DexCompilerInputBundleCodec.read(
                input = input,
                limits = capability.limits.toCodecLimits(capabilities),
            ) { identity, entryInput ->
                ensureActive()
                val expected = request.inputIdentities.getOrNull(entryIndex)
                    ?: failInvalidRequest("Input bundle contains an unexpected entry")
                if (identity != expected) {
                    failInvalidRequest("Input bundle identities differ from the compile request")
                }
                val destination = when (identity.role) {
                    DexCompilerInputRole.PROGRAM -> workspace.programJar
                    DexCompilerInputRole.CLASSPATH -> workspace.classpathJar(identity.ordinal)
                }
                val validated = BoundedJarValidator.copyAndValidateInput(
                    input = entryInput,
                    destination = destination,
                    expectedSizeBytes = identity.sizeBytes,
                    expectedSha256 = identity.contentSha256,
                    maximumCompressedBytes = when (identity.role) {
                        DexCompilerInputRole.PROGRAM -> capabilities.limits.maxCompressedProgramBytes
                        DexCompilerInputRole.CLASSPATH -> capability.limits.maxCompressedClasspathJarBytes
                    },
                    limits = capabilities.limits,
                    requireClassEntries = identity.role == DexCompilerInputRole.PROGRAM,
                    inputLabel = when (identity.role) {
                        DexCompilerInputRole.PROGRAM -> "Program"
                        DexCompilerInputRole.CLASSPATH -> "Classpath JAR ${identity.ordinal}"
                    },
                )
                aggregate.add(validated)
                if (identity.role == DexCompilerInputRole.CLASSPATH) classpathJars += destination
                entryIndex++
                ensureActive()
            }
        } catch (error: DexCompilerInputBundleException) {
            throw DexCompileFailure(
                if (error.error == DexCompilerInputBundleError.LIMIT_EXCEEDED) {
                    DexCompilerErrorCode.INPUT_TOO_LARGE
                } else {
                    DexCompilerErrorCode.INVALID_ARCHIVE
                },
                DexCompilerFailurePhase.INPUT_VALIDATION,
                error.message ?: "Input bundle is invalid",
                error,
            )
        }

        if (entryIndex != request.inputIdentities.size || summary.identities != request.inputIdentities) {
            failInvalidRequest("Input bundle identities differ from the compile request")
        }
        if (summary.sizeBytes != request.inputBundleSizeBytes) {
            failInvalidRequest("Input bundle size differs from the compile request")
        }
        if (summary.contentSha256 != request.inputBundleSha256) {
            failInvalidRequest("Input bundle SHA-256 differs from the compile request")
        }
        ensureActive()
        return MaterializedDexInputs(workspace.programJar, classpathJars.toList())
    }

    private fun DexCompilerClasspathBundleLimits.toCodecLimits(
        capabilities: DexCompilerCapabilities,
    ) = DexCompilerInputBundleLimits(
        maxEntryCount = maxClasspathJarCount + 1,
        maxEntryBytes = maxOf(
            capabilities.limits.maxCompressedProgramBytes,
            maxCompressedClasspathJarBytes,
        ),
        maxBundleBytes = maxInputBundleBytes,
    )

    private class AggregateInputBudget(
        private val limits: DexCompilerClasspathBundleLimits,
    ) {
        private var archiveEntries = 0L
        private var uncompressedBytes = 0L
        private var classBytes = 0L

        fun add(input: ValidatedJar) {
            archiveEntries = checkedAdd(archiveEntries, input.archiveEntryCount.toLong())
            uncompressedBytes = checkedAdd(uncompressedBytes, input.uncompressedSizeBytes)
            classBytes = checkedAdd(classBytes, input.totalClassBytes)
            if (
                archiveEntries > limits.maxTotalInputArchiveEntries.toLong() ||
                uncompressedBytes > limits.maxTotalUncompressedInputBytes ||
                classBytes > limits.maxTotalInputClassBytes
            ) {
                throw DexCompileFailure(
                    DexCompilerErrorCode.INPUT_TOO_LARGE,
                    DexCompilerFailurePhase.INPUT_VALIDATION,
                    "Input bundle exceeds the provider aggregate archive budget",
                )
            }
        }

        private fun checkedAdd(left: Long, right: Long): Long = try {
            Math.addExact(left, right)
        } catch (error: ArithmeticException) {
            throw DexCompileFailure(
                DexCompilerErrorCode.INPUT_TOO_LARGE,
                DexCompilerFailurePhase.INPUT_VALIDATION,
                "Input bundle aggregate archive budget overflows",
                error,
            )
        }
    }

    private fun failInvalidRequest(message: String): Nothing = throw DexCompileFailure(
        DexCompilerErrorCode.INVALID_REQUEST,
        DexCompilerFailurePhase.INPUT_VALIDATION,
        message,
    )
}
