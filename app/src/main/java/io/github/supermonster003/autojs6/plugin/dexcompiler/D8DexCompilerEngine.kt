package io.github.supermonster003.autojs6.plugin.dexcompiler

import android.annotation.TargetApi
import android.os.Build
import com.android.tools.r8.CompilationFailedException
import com.android.tools.r8.CompilationMode
import com.android.tools.r8.D8
import com.android.tools.r8.D8Command
import com.android.tools.r8.DiagnosticsHandler
import com.android.tools.r8.OutputMode
import com.android.tools.r8.origin.Origin
import org.autojs.plugin.dexcompiler.api.DexCompileRequest
import org.autojs.plugin.dexcompiler.api.DexCompilerErrorCode
import org.autojs.plugin.dexcompiler.api.DexCompilerFailurePhase
import org.autojs.plugin.dexcompiler.api.DexCompilerMode
import java.io.File
import java.io.IOException

internal class D8DexCompilerEngine(
    private val runtimeLibraries: RuntimeLibrarySet,
    private val sdkInt: () -> Int = { Build.VERSION.SDK_INT },
    private val commandRunner: D8CommandRunner = AndroidD8CommandRunner,
    private val cliRunner: D8CliRunner = AndroidD8CliRunner,
) {
    fun compile(
        request: DexCompileRequest,
        programJar: File,
        classpathJars: List<File> = emptyList(),
        outputDirectory: File,
        artifactZip: File,
        ensureActive: () -> Unit,
        beforePackaging: () -> Unit,
    ): DexArtifact {
        val inputs = D8InputFiles(programJar, classpathJars.toList())
        val diagnostics = D8DiagnosticCollector(
            requestedByteLimit = request.diagnosticByteLimit,
            originResolver = D8DiagnosticOriginResolver.create(
                programJar = inputs.programJar,
                classpathJars = inputs.classpathJars,
                runtimeLibraries = runtimeLibraries.files,
                outputDirectory = outputDirectory,
            ),
        )
        ensureActive()
        try {
            if (sdkInt() >= Build.VERSION_CODES.O) {
                commandRunner.run(request, inputs, outputDirectory, runtimeLibraries.files, diagnostics)
            } else {
                val arguments = mutableListOf(
                    "--output", outputDirectory.absolutePath,
                    request.mode.toD8ExecutionMode().cliFlag,
                    "--min-api", request.minApi.toString(),
                )
                runtimeLibraries.files.forEach {
                    arguments += "--lib"
                    arguments += it.absolutePath
                }
                inputs.classpathJars.forEach {
                    arguments += "--classpath"
                    arguments += it.absolutePath
                }
                arguments += inputs.programJar.absolutePath
                cliRunner.run(arguments.toTypedArray(), diagnostics)
            }
        } catch (error: CompilationFailedException) {
            diagnostics.recordTerminalFailure()
            throw DexCompileFailure(
                DexCompilerErrorCode.COMPILATION_FAILED,
                DexCompilerFailurePhase.COMPILATION,
                "D8 compilation failed",
                error,
                diagnostics.snapshot(),
            )
        } catch (error: IOException) {
            throw DexCompileFailure(
                DexCompilerErrorCode.STORAGE_EXHAUSTED,
                DexCompilerFailurePhase.COMPILATION,
                error.message ?: "D8 could not access its private workspace",
                error,
            )
        } catch (error: DexCompileFailure) {
            throw error
        } catch (error: VirtualMachineError) {
            throw error
        } catch (error: Throwable) {
            diagnostics.recordTerminalFailure()
            throw DexCompileFailure(
                DexCompilerErrorCode.COMPILATION_FAILED,
                DexCompilerFailurePhase.COMPILATION,
                "D8 compilation failed",
                error,
                diagnostics.snapshot(),
            )
        }
        ensureActive()
        beforePackaging()
        ensureActive()
        return DexIndexedOutputPackager.packageOutput(
            d8OutputDirectory = outputDirectory,
            destination = artifactZip,
            maximumOutputBytes = request.maxOutputBytes,
            maximumDexEntries = DexCompilerRuntime.capabilities(runtimeLibraries).limits.maxDexEntries,
        ).copy(diagnostics = diagnostics.snapshot())
    }
}

internal data class D8InputFiles(
    val programJar: File,
    val classpathJars: List<File>,
)

internal fun interface D8CommandRunner {
    fun run(
        request: DexCompileRequest,
        inputs: D8InputFiles,
        outputDirectory: File,
        runtimeLibraries: List<File>,
        diagnosticsHandler: DiagnosticsHandler,
    )
}

internal fun interface D8CliRunner {
    fun run(arguments: Array<String>, diagnosticsHandler: DiagnosticsHandler)
}

/**
 * Maps the V1 wire mode to D8's two invocation forms.
 *
 * [DexCompilerMode.RELEASE] means only [CompilationMode.RELEASE] (or D8's matching CLI flag).
 * It does not select R8 or add keep rules, shrinking, minification, obfuscation, mapping, seeds,
 * or usage-output semantics to this provider.
 */
internal fun DexCompilerMode.toD8ExecutionMode(): D8ExecutionMode = when (this) {
    DexCompilerMode.DEBUG -> D8ExecutionMode(CompilationMode.DEBUG, "--debug")
    DexCompilerMode.RELEASE -> D8ExecutionMode(CompilationMode.RELEASE, "--release")
}

internal data class D8ExecutionMode(
    val compilationMode: CompilationMode,
    val cliFlag: String,
)

private object AndroidD8CommandRunner : D8CommandRunner {
    @TargetApi(Build.VERSION_CODES.O)
    override fun run(
        request: DexCompileRequest,
        inputs: D8InputFiles,
        outputDirectory: File,
        runtimeLibraries: List<File>,
        diagnosticsHandler: DiagnosticsHandler,
    ) {
        val builder = D8Command.builder(diagnosticsHandler)
            .addProgramFiles(inputs.programJar.toPath())
            .setOutput(outputDirectory.toPath(), OutputMode.DexIndexed)
            .setMode(request.mode.toD8ExecutionMode().compilationMode)
            .setMinApiLevel(request.minApi)
        runtimeLibraries.forEach { builder.addLibraryFiles(it.toPath()) }
        inputs.classpathJars.forEach { builder.addClasspathFiles(it.toPath()) }
        D8.run(builder.build())
    }
}

private object AndroidD8CliRunner : D8CliRunner {
    override fun run(arguments: Array<String>, diagnosticsHandler: DiagnosticsHandler) {
        D8.run(D8Command.parse(arguments, Origin.root(), diagnosticsHandler).build())
    }
}
