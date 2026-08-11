package io.github.supermonster003.autojs6.plugin.dexcompiler

import com.android.tools.r8.CompilationFailedException
import com.android.tools.r8.Diagnostic
import com.android.tools.r8.origin.Origin
import com.android.tools.r8.position.Position
import org.autojs.plugin.dexcompiler.api.DexCompilerContract
import org.autojs.plugin.dexcompiler.api.DexCompileError
import org.autojs.plugin.dexcompiler.api.DexCompilerCodec
import org.autojs.plugin.dexcompiler.api.DexCompilerDiagnostic
import org.autojs.plugin.dexcompiler.api.DexCompilerDiagnosticSeverity
import org.autojs.plugin.dexcompiler.api.DexCompilerErrorCode
import org.autojs.plugin.dexcompiler.api.DexCompilerFailurePhase
import org.autojs.plugin.dexcompiler.api.DexCompilerValidation
import org.autojs.plugin.dexcompiler.api.DexRequestId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files
import java.util.UUID

class D8DiagnosticCollectorTest {
    @Test
    fun retainsOnlyStableErrorSeverity() {
        val collector = D8DiagnosticCollector(DexCompilerContract.MAX_DIAGNOSTIC_BYTES)

        collector.info(TestDiagnostic("plain info"))
        collector.warning(MissingDefinitionsDiagnostic("missing reference"))
        collector.error(DuplicateTypesDiagnostic("duplicate class"))
        collector.error(TestDiagnostic("plain error"))

        val diagnostics = collector.snapshot()
        DexCompilerValidation.validateDiagnostics(diagnostics)
        assertEquals(
            listOf(
                DexCompilerDiagnosticSeverity.ERROR,
                DexCompilerDiagnosticSeverity.ERROR,
            ),
            diagnostics.map { it.severity },
        )
        assertEquals(listOf("D8.ERROR", "D8.ERROR"), diagnostics.map { it.code })
    }

    @Test
    fun enforcesCountByteAndCodePointLimitsWithTruncationSentinel() {
        val countCollector = D8DiagnosticCollector(DexCompilerContract.MAX_DIAGNOSTIC_BYTES)
        repeat(513) { countCollector.error(TestDiagnostic("e")) }
        val countDiagnostics = countCollector.snapshot()
        DexCompilerValidation.validateDiagnostics(countDiagnostics)
        assertEquals(512, countDiagnostics.size)
        assertEquals("D8.DIAGNOSTICS_TRUNCATED", countDiagnostics.last().code)

        val byteCollector = D8DiagnosticCollector(32)
        byteCollector.error(TestDiagnostic("x".repeat(100)))
        val byteDiagnostics = byteCollector.snapshot()
        DexCompilerValidation.validateDiagnostics(byteDiagnostics)
        assertEquals(listOf("D8.ERROR"), byteDiagnostics.map { it.code })
        assertTrue(retainedUtf8Bytes(byteDiagnostics) <= 32)

        val codePointCollector = D8DiagnosticCollector(DexCompilerContract.MAX_DIAGNOSTIC_BYTES)
        codePointCollector.error(TestDiagnostic("a".repeat(5_000)))
        val codePointDiagnostics = codePointCollector.snapshot()
        DexCompilerValidation.validateDiagnostics(codePointDiagnostics)
        assertEquals(
            DexCompilerContract.MAX_DIAGNOSTIC_MESSAGE_CODE_POINTS,
            codePointDiagnostics.first().message.codePointCount(0, codePointDiagnostics.first().message.length),
        )
        assertEquals("D8.DIAGNOSTICS_TRUNCATED", codePointDiagnostics.last().code)
        assertTrue(retainedUtf8Bytes(codePointDiagnostics) <= DexCompilerContract.MAX_DIAGNOSTIC_BYTES)

        val zeroBudgetCollector = D8DiagnosticCollector(0)
        zeroBudgetCollector.error(TestDiagnostic("not retained"))
        zeroBudgetCollector.recordTerminalFailure()
        assertTrue(zeroBudgetCollector.snapshot().isEmpty())

        val tooSmallTerminalCollector = D8DiagnosticCollector(8)
        tooSmallTerminalCollector.recordTerminalFailure()
        assertTrue(tooSmallTerminalCollector.snapshot().isEmpty())

        val terminalCollector = D8DiagnosticCollector(64)
        terminalCollector.recordTerminalFailure()
        assertEquals(
            listOf("D8.COMPILATION_FAILED" to "D8 compilation failed"),
            terminalCollector.snapshot().map { it.code to it.message },
        )
    }

    @Test
    fun normalizesControlCharactersAndIsolatesHostileDiagnosticCallbacks() {
        val collector = D8DiagnosticCollector(DexCompilerContract.MAX_DIAGNOSTIC_BYTES)

        collector.error(ThrowingDiagnostic())
        collector.error(TestDiagnostic("\ud800\u0000alpha\nbeta\tgamma\u007f"))

        val diagnostics = collector.snapshot()
        assertEquals(1, diagnostics.size)
        assertEquals("\ufffd alpha beta gamma", diagnostics.single().message)
        assertFalse(diagnostics.single().message.codePoints().anyMatch { Character.isISOControl(it) })
        DexCompilerValidation.validateDiagnostics(diagnostics)
    }

    @Test
    fun api26CommandHandlerAndCompilationExceptionProduceBoundedTerminalDiagnostic() {
        val root = Files.createTempDirectory("d8-diagnostic-terminal-test").toFile()
        try {
            val runtimeFile = root.resolve("runtime.jar").apply { writeBytes(byteArrayOf(1)) }
            val runtime = RuntimeLibrarySet.fromFiles(listOf(runtimeFile))
            val program = root.resolve("program.jar").apply { writeBytes(byteArrayOf(2)) }
            val request = TestData.request(program.readBytes(), runtime).copy(diagnosticByteLimit = 128)
            val runner = D8CommandRunner { _, _, _, _, handler ->
                handler.warning(TestDiagnostic("w".repeat(10_000)))
                handler.error(ThrowingDiagnostic())
                throw CompilationFailedException("terminal\u0000failure")
            }

            val failure = assertThrows(DexCompileFailure::class.java) {
                D8DexCompilerEngine(
                    runtimeLibraries = runtime,
                    sdkInt = { 26 },
                    commandRunner = runner,
                ).compile(
                    request = request,
                    programJar = program,
                    outputDirectory = root.resolve("d8").apply { mkdir() },
                    artifactZip = root.resolve("artifact.zip"),
                    ensureActive = {},
                    beforePackaging = {},
                )
            }

            assertEquals(DexCompilerErrorCode.COMPILATION_FAILED, failure.code)
            assertEquals(DexCompilerFailurePhase.COMPILATION, failure.phase)
            DexCompilerValidation.validateDiagnostics(failure.diagnostics)
            assertEquals(
                listOf("D8.COMPILATION_FAILED"),
                failure.diagnostics.map { it.code },
            )
            assertEquals("D8 compilation failed", failure.diagnostics.single().message)
            assertTrue(retainedUtf8Bytes(failure.diagnostics) <= request.diagnosticByteLimit)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun failureCarrierIsImmutableAndSurvivesV1ErrorCodec() {
        val source = mutableListOf(
            DexCompilerDiagnostic(
                severity = DexCompilerDiagnosticSeverity.ERROR,
                code = "D8.ERROR",
                message = "error",
            ),
        )
        val failure = DexCompileFailure(
            code = DexCompilerErrorCode.COMPILATION_FAILED,
            phase = DexCompilerFailurePhase.COMPILATION,
            message = "failed",
            diagnostics = source,
        )

        source.clear()
        assertEquals(1, failure.diagnostics.size)
        assertThrows(UnsupportedOperationException::class.java) {
            (failure.diagnostics as MutableList<DexCompilerDiagnostic>).clear()
        }
        val decoded = DexCompilerCodec.decodeError(
            DexCompilerCodec.encodeError(
                DexCompileError(
                    requestId = DexRequestId.fromUuid(UUID.fromString("00000000-0000-0000-0000-000000000002")),
                    code = failure.code,
                    phase = failure.phase,
                    message = failure.message ?: "failed",
                    retryable = false,
                    diagnostics = failure.diagnostics,
                ),
            ),
        )
        assertEquals(listOf("D8.ERROR"), decoded.diagnostics.map { it.code })
        assertEquals(listOf("error"), decoded.diagnostics.map { it.message })
    }

    private fun retainedUtf8Bytes(diagnostics: Collection<DexCompilerDiagnostic>): Int = diagnostics.sumOf {
        it.code.toByteArray(Charsets.UTF_8).size + it.message.toByteArray(Charsets.UTF_8).size
    }

    private open class TestDiagnostic(private val message: String) : Diagnostic {
        override fun getOrigin(): Origin = Origin.unknown()

        override fun getPosition(): Position = Position.UNKNOWN

        override fun getDiagnosticMessage(): String = message
    }

    private class MissingDefinitionsDiagnostic(message: String) : TestDiagnostic(message)

    private class DuplicateTypesDiagnostic(message: String) : TestDiagnostic(message)

    private class ThrowingDiagnostic : Diagnostic {
        override fun getOrigin(): Origin = Origin.unknown()

        override fun getPosition(): Position = Position.UNKNOWN

        override fun getDiagnosticMessage(): String = throw IllegalStateException("hostile diagnostic")
    }
}
