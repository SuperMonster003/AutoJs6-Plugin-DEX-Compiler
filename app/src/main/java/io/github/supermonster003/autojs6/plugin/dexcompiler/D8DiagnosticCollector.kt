package io.github.supermonster003.autojs6.plugin.dexcompiler

import com.android.tools.r8.Diagnostic
import com.android.tools.r8.DiagnosticsHandler
import com.android.tools.r8.DiagnosticsLevel
import org.autojs.plugin.dexcompiler.api.DexCompilerContract
import org.autojs.plugin.dexcompiler.api.DexCompilerDiagnostic
import org.autojs.plugin.dexcompiler.api.DexCompilerDiagnosticSeverity
import java.util.ArrayList
import java.util.Collections

/** Collects only failure diagnostics. D8 info/warnings remain a non-gating future enhancement. */
internal class D8DiagnosticCollector(requestedByteLimit: Int) : DiagnosticsHandler {
    private val byteLimit = requestedByteLimit.coerceIn(0, DexCompilerContract.MAX_DIAGNOSTIC_BYTES)
    private val lock = Any()
    private val retained = ArrayList<DexCompilerDiagnostic>()
    private var retainedBytes = 0
    private var omitted = false

    override fun info(diagnostic: Diagnostic) = Unit

    override fun warning(diagnostic: Diagnostic) = Unit

    override fun error(diagnostic: Diagnostic) {
        try {
            val normalized = normalizeMessage(diagnostic.diagnosticMessage)
            synchronized(lock) {
                val available = availableForActualError()
                val bounded = boundedDiagnostic(ERROR_CODE, normalized.text, available)
                if (bounded == null || retained.size >= MAX_DIAGNOSTIC_COUNT) {
                    omitted = true
                    return
                }
                append(bounded.value)
                omitted = omitted || normalized.truncated || bounded.truncated
            }
        } catch (error: VirtualMachineError) {
            throw error
        } catch (_: Throwable) {
            // A malformed D8 diagnostic must not replace or mask the compiler's real outcome.
        }
    }

    override fun modifyDiagnosticsLevel(level: DiagnosticsLevel, diagnostic: Diagnostic): DiagnosticsLevel = level

    fun recordTerminalFailure() {
        try {
            synchronized(lock) {
                if (retained.any { it.code == ERROR_CODE || it.code == TERMINAL_CODE }) return
                val terminal = boundedDiagnostic(TERMINAL_CODE, TERMINAL_MESSAGE, byteLimit)
                    ?: return
                while (retained.isNotEmpty() && !canAppend(terminal.value)) {
                    removeLast()
                    omitted = true
                }
                if (canAppend(terminal.value)) append(terminal.value)
            }
        } catch (error: VirtualMachineError) {
            throw error
        } catch (_: Throwable) {
            // Diagnostics remain advisory even when building the terminal fallback.
        }
    }

    fun snapshot(): List<DexCompilerDiagnostic> = synchronized(lock) {
        val result = ArrayList(retained)
        var resultBytes = retainedBytes
        if (omitted && diagnosticBytes(TRUNCATION_SENTINEL) <= byteLimit) {
            while (result.size >= MAX_DIAGNOSTIC_COUNT) {
                resultBytes -= diagnosticBytes(result.removeAt(result.lastIndex))
            }
            while (
                result.size > 1 &&
                diagnosticBytes(TRUNCATION_SENTINEL) > byteLimit - resultBytes
            ) {
                resultBytes -= diagnosticBytes(result.removeAt(result.lastIndex))
            }
            if (diagnosticBytes(TRUNCATION_SENTINEL) <= byteLimit - resultBytes) {
                result += TRUNCATION_SENTINEL
            }
        }
        immutableDiagnostics(result)
    }

    private fun availableForActualError(): Int {
        return byteLimit - retainedBytes
    }

    private fun boundedDiagnostic(code: String, message: String, availableBytes: Int): BoundedDiagnostic? {
        val messageBytes = availableBytes - utf8Size(code)
        if (messageBytes < 1) return null
        val boundedMessage = truncateUtf8(message, messageBytes)
        if (boundedMessage.text.isEmpty()) return null
        return BoundedDiagnostic(
            value = DexCompilerDiagnostic(
                severity = DexCompilerDiagnosticSeverity.ERROR,
                code = code,
                message = boundedMessage.text,
            ),
            truncated = boundedMessage.truncated,
        )
    }

    private fun canAppend(value: DexCompilerDiagnostic): Boolean {
        if (retained.size >= MAX_DIAGNOSTIC_COUNT) return false
        return diagnosticBytes(value) <= byteLimit - retainedBytes
    }

    private fun append(value: DexCompilerDiagnostic) {
        retained += value
        retainedBytes += diagnosticBytes(value)
    }

    private fun removeLast() {
        retainedBytes -= diagnosticBytes(retained.removeAt(retained.lastIndex))
    }

    private fun normalizeMessage(message: String): BoundedText {
        val output = StringBuilder(minOf(message.length, DexCompilerContract.MAX_DIAGNOSTIC_MESSAGE_CODE_POINTS))
        var inputIndex = 0
        var scannedCodePoints = 0
        var previousWasSpace = false
        while (
            inputIndex < message.length &&
            scannedCodePoints < DexCompilerContract.MAX_DIAGNOSTIC_MESSAGE_CODE_POINTS
        ) {
            val codePoint = message.codePointAt(inputIndex)
            inputIndex += Character.charCount(codePoint)
            scannedCodePoints += 1
            val normalized = when {
                codePoint in HIGH_SURROGATE..LOW_SURROGATE -> REPLACEMENT_CODE_POINT
                Character.isISOControl(codePoint) -> SPACE_CODE_POINT
                else -> codePoint
            }
            if (normalized == SPACE_CODE_POINT && previousWasSpace) continue
            output.appendCodePoint(normalized)
            previousWasSpace = normalized == SPACE_CODE_POINT
        }
        val text = output.toString().trim().ifBlank { UNAVAILABLE_MESSAGE }
        return BoundedText(text, inputIndex < message.length)
    }

    private fun truncateUtf8(value: String, maximumBytes: Int): BoundedText {
        var index = 0
        var bytes = 0
        while (index < value.length) {
            val codePoint = value.codePointAt(index)
            val encodedBytes = utf8Size(String(Character.toChars(codePoint)))
            if (encodedBytes > maximumBytes - bytes) break
            bytes += encodedBytes
            index += Character.charCount(codePoint)
        }
        return BoundedText(value.substring(0, index).trimEnd(), index < value.length)
    }

    private fun diagnosticBytes(value: DexCompilerDiagnostic): Int =
        utf8Size(value.code) + utf8Size(value.message)

    private fun utf8Size(value: String): Int = value.toByteArray(Charsets.UTF_8).size

    private data class BoundedDiagnostic(
        val value: DexCompilerDiagnostic,
        val truncated: Boolean,
    )

    private data class BoundedText(
        val text: String,
        val truncated: Boolean,
    )

    private companion object {
        const val MAX_DIAGNOSTIC_COUNT = 512
        const val SPACE_CODE_POINT = 0x20
        const val REPLACEMENT_CODE_POINT = 0xfffd
        const val HIGH_SURROGATE = 0xd800
        const val LOW_SURROGATE = 0xdfff
        const val ERROR_CODE = "D8.ERROR"
        const val TERMINAL_CODE = "D8.COMPILATION_FAILED"
        const val TRUNCATION_CODE = "D8.DIAGNOSTICS_TRUNCATED"
        const val UNAVAILABLE_MESSAGE = "D8 diagnostic message unavailable"
        const val TERMINAL_MESSAGE = "D8 compilation failed"
        val TRUNCATION_SENTINEL = DexCompilerDiagnostic(
            severity = DexCompilerDiagnosticSeverity.WARNING,
            code = TRUNCATION_CODE,
            message = "Truncated",
        )
    }
}

internal fun immutableDiagnostics(
    values: Collection<DexCompilerDiagnostic>,
): List<DexCompilerDiagnostic> = Collections.unmodifiableList(ArrayList(values))
