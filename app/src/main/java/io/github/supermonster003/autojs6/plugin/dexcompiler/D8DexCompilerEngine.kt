package io.github.supermonster003.autojs6.plugin.dexcompiler

import android.annotation.TargetApi
import android.os.Build
import com.android.tools.r8.CompilationFailedException
import com.android.tools.r8.CompilationMode
import com.android.tools.r8.D8
import com.android.tools.r8.D8Command
import com.android.tools.r8.DiagnosticsHandler
import com.android.tools.r8.OutputMode
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
        val diagnostics = D8DiagnosticCollector(request.diagnosticByteLimit)
        val inputs = D8InputFiles(programJar, classpathJars.toList())
        ensureActive()
        try {
            if (sdkInt() >= Build.VERSION_CODES.O) {
                commandRunner.run(request, inputs, outputDirectory, runtimeLibraries.files, diagnostics)
            } else {
                val arguments = mutableListOf(
                    "--output", outputDirectory.absolutePath,
                    if (request.mode == DexCompilerMode.DEBUG) "--debug" else "--release",
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
                cliRunner.run(arguments.toTypedArray())
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
        )
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
    fun run(arguments: Array<String>)
}

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
            .setMode(request.mode.toCompilationMode())
            .setMinApiLevel(request.minApi)
        runtimeLibraries.forEach { builder.addLibraryFiles(it.toPath()) }
        inputs.classpathJars.forEach { builder.addClasspathFiles(it.toPath()) }
        D8.run(builder.build())
    }

    private fun DexCompilerMode.toCompilationMode(): CompilationMode = when (this) {
        DexCompilerMode.DEBUG -> CompilationMode.DEBUG
        DexCompilerMode.RELEASE -> CompilationMode.RELEASE
    }
}

private object AndroidD8CliRunner : D8CliRunner {
    override fun run(arguments: Array<String>) {
        D8.main(arguments)
    }
}
