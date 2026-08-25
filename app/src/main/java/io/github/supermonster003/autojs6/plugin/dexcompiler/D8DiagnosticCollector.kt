package io.github.supermonster003.autojs6.plugin.dexcompiler

import com.android.tools.r8.Diagnostic
import com.android.tools.r8.DiagnosticsHandler
import com.android.tools.r8.DiagnosticsLevel
import com.android.tools.r8.origin.ArchiveEntryOrigin
import com.android.tools.r8.origin.Origin
import com.android.tools.r8.position.MethodPosition
import com.android.tools.r8.position.Position
import com.android.tools.r8.position.TextPosition
import com.android.tools.r8.position.TextRange
import org.autojs.plugin.dexcompiler.api.DexCompilerContract
import org.autojs.plugin.dexcompiler.api.DexCompilerDiagnostic
import org.autojs.plugin.dexcompiler.api.DexCompilerDiagnosticPosition
import org.autojs.plugin.dexcompiler.api.DexCompilerDiagnosticSeverity
import java.io.File
import java.text.Normalizer
import java.util.ArrayList
import java.util.Collections
import java.util.Locale

/**
 * Collects the complete D8 callback stream with severity-aware retention.
 *
 * Errors may evict warnings or info entries, and warnings may evict info entries, so advisory
 * output cannot consume the request's 64 KiB budget before a failure arrives. Filesystem origins
 * are mapped to path-free logical labels; raw provider paths are neither retained nor serialized.
 */
internal class D8DiagnosticCollector(
    requestedByteLimit: Int,
    private val originResolver: D8DiagnosticOriginResolver = D8DiagnosticOriginResolver.NONE,
) : DiagnosticsHandler {
    private val byteLimit = requestedByteLimit.coerceIn(0, DexCompilerContract.MAX_DIAGNOSTIC_BYTES)
    private val lock = Any()
    private val retained = ArrayList<DexCompilerDiagnostic>()
    private var retainedBytes = 0
    private var omitted = false

    override fun info(diagnostic: Diagnostic) = record(
        DexCompilerDiagnosticSeverity.INFO,
        INFO_CODE,
        diagnostic,
    )

    override fun warning(diagnostic: Diagnostic) = record(
        DexCompilerDiagnosticSeverity.WARNING,
        WARNING_CODE,
        diagnostic,
    )

    override fun error(diagnostic: Diagnostic) = record(
        DexCompilerDiagnosticSeverity.ERROR,
        ERROR_CODE,
        diagnostic,
    )

    override fun modifyDiagnosticsLevel(level: DiagnosticsLevel, diagnostic: Diagnostic): DiagnosticsLevel = level

    fun recordTerminalFailure() {
        try {
            synchronized(lock) {
                if (retained.any { it.code == ERROR_CODE || it.code == TERMINAL_CODE }) return
                recordLocked(
                    severity = DexCompilerDiagnosticSeverity.ERROR,
                    code = TERMINAL_CODE,
                    normalized = BoundedText(TERMINAL_MESSAGE, truncated = false),
                    metadata = D8DiagnosticMetadata(),
                )
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
        val sentinelBytes = diagnosticBytes(TRUNCATION_SENTINEL)
        if (omitted && sentinelBytes <= byteLimit) {
            while (
                result.size > 1 && (
                    result.size >= MAX_DIAGNOSTIC_COUNT || sentinelBytes > byteLimit - resultBytes
                )
            ) {
                val lowestSeverity = result.minOf { it.severity.wireCode }
                val removeIndex = result.indexOfLast { it.severity.wireCode == lowestSeverity }
                resultBytes -= diagnosticBytes(result.removeAt(removeIndex))
            }
            if (result.size < MAX_DIAGNOSTIC_COUNT && sentinelBytes <= byteLimit - resultBytes) {
                result += TRUNCATION_SENTINEL
            }
        }
        immutableDiagnostics(result)
    }

    private fun record(
        severity: DexCompilerDiagnosticSeverity,
        code: String,
        diagnostic: Diagnostic,
    ) {
        try {
            val normalized = normalizeMessage(diagnostic.diagnosticMessage)
            val metadata = originResolver.metadata(diagnostic)
            synchronized(lock) {
                recordLocked(severity, code, normalized, metadata)
            }
        } catch (error: VirtualMachineError) {
            throw error
        } catch (_: Throwable) {
            // A malformed D8 diagnostic must not replace or mask the compiler's real outcome.
        }
    }

    private fun recordLocked(
        severity: DexCompilerDiagnosticSeverity,
        code: String,
        normalized: BoundedText,
        metadata: D8DiagnosticMetadata,
    ) {
        val full = boundedDiagnostic(severity, code, normalized.text, byteLimit, metadata)
        if (full == null) {
            omitted = true
            return
        }
        while (retained.size >= MAX_DIAGNOSTIC_COUNT || !canAppend(full.value)) {
            val lowerPriorityIndex = retained.indexOfLast { it.severity.wireCode < severity.wireCode }
            if (lowerPriorityIndex < 0) break
            removeAt(lowerPriorityIndex)
            omitted = true
        }
        if (retained.size >= MAX_DIAGNOSTIC_COUNT) {
            omitted = true
            return
        }
        val bounded = boundedDiagnostic(
            severity = severity,
            code = code,
            message = normalized.text,
            availableBytes = byteLimit - retainedBytes,
            metadata = metadata,
        )
        if (bounded == null) {
            omitted = true
            return
        }
        append(bounded.value)
        omitted = omitted || normalized.truncated || metadata.truncated || bounded.truncated
    }

    private fun boundedDiagnostic(
        severity: DexCompilerDiagnosticSeverity,
        code: String,
        message: String,
        availableBytes: Int,
        metadata: D8DiagnosticMetadata,
    ): BoundedDiagnostic? {
        var origin = metadata.origin
        var entry = metadata.entry
        var position = metadata.position
        var metadataDropped = false
        while (true) {
            val fixedBytes = utf8Size(code) +
                (origin?.let(::utf8Size) ?: 0) +
                (entry?.let(::utf8Size) ?: 0) +
                positionBytes(position)
            val messageBytes = availableBytes - fixedBytes
            if (messageBytes > 0) {
                val boundedMessage = truncateUtf8(message, messageBytes)
                if (boundedMessage.text.isNotEmpty()) {
                    return BoundedDiagnostic(
                        value = DexCompilerDiagnostic(
                            severity = severity,
                            code = code,
                            message = boundedMessage.text,
                            origin = origin,
                            entry = entry,
                            position = position,
                        ),
                        truncated = metadataDropped || boundedMessage.truncated,
                    )
                }
            }
            when {
                entry != null -> entry = null
                position != null -> position = null
                origin != null -> origin = null
                else -> return null
            }
            metadataDropped = true
        }
    }

    private fun canAppend(value: DexCompilerDiagnostic): Boolean {
        if (retained.size >= MAX_DIAGNOSTIC_COUNT) return false
        return diagnosticBytes(value) <= byteLimit - retainedBytes
    }

    private fun append(value: DexCompilerDiagnostic) {
        retained += value
        retainedBytes += diagnosticBytes(value)
    }

    private fun removeAt(index: Int) {
        retainedBytes -= diagnosticBytes(retained.removeAt(index))
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
        val normalized = output.toString().trim().ifBlank { UNAVAILABLE_MESSAGE }
        val redacted = originResolver.redact(normalized).ifBlank { UNAVAILABLE_MESSAGE }
        val boundedRedacted = truncateCodePoints(
            redacted,
            DexCompilerContract.MAX_DIAGNOSTIC_MESSAGE_CODE_POINTS,
        )
        return BoundedText(
            text = boundedRedacted.text,
            truncated = inputIndex < message.length || boundedRedacted.truncated,
        )
    }

    private fun truncateCodePoints(value: String, maximumCodePoints: Int): BoundedText {
        val count = value.codePointCount(0, value.length)
        if (count <= maximumCodePoints) return BoundedText(value, truncated = false)
        val end = value.offsetByCodePoints(0, maximumCodePoints)
        return BoundedText(value.substring(0, end).trimEnd(), truncated = true)
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
        utf8Size(value.code) +
            utf8Size(value.message) +
            (value.origin?.let(::utf8Size) ?: 0) +
            (value.entry?.let(::utf8Size) ?: 0) +
            positionBytes(value.position)

    private fun positionBytes(value: DexCompilerDiagnosticPosition?): Int {
        if (value == null) return 0
        return listOf(value.line, value.column, value.endLine, value.endColumn)
            .count { it != null } * Int.SIZE_BYTES +
            listOf(value.offset, value.endOffset).count { it != null } * Long.SIZE_BYTES
    }

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
        const val INFO_CODE = "D8.INFO"
        const val WARNING_CODE = "D8.WARNING"
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

internal class D8DiagnosticOriginResolver private constructor(
    private val labelsByPath: Map<String, String>,
    private val exactRedactions: List<Pair<String, String>>,
) {
    fun metadata(diagnostic: Diagnostic): D8DiagnosticMetadata {
        val diagnosticOrigin = runCatching { diagnostic.origin }.getOrNull()
        var current = diagnosticOrigin
        var origin: String? = null
        var entry: String? = null
        var truncated = false
        var depth = 0
        while (current != null && depth < MAX_ORIGIN_DEPTH) {
            val value = current
            if (value is ArchiveEntryOrigin && entry == null) {
                val bounded = safeEntry(runCatching { value.entryName }.getOrNull())
                entry = bounded?.text
                truncated = truncated || bounded?.truncated == true
            }
            if (origin == null) {
                origin = runCatching { value.part() }
                    .getOrNull()
                    ?.let(::pathKey)
                    ?.let(labelsByPath::get)
            }
            current = runCatching { value.parent() }.getOrNull()
            depth += 1
        }
        return D8DiagnosticMetadata(
            origin = origin ?: UNKNOWN_ORIGIN,
            entry = entry,
            position = safePosition(runCatching { diagnostic.position }.getOrNull()),
            truncated = truncated,
        )
    }

    fun redact(value: String): String {
        var redacted = value
        exactRedactions.forEach { (path, label) ->
            redacted = redacted.replace(path, "<$label>", ignoreCase = WINDOWS_PATHS)
        }
        redacted = FILE_URI.replace(redacted, REDACTED_PATH)
        redacted = WINDOWS_ABSOLUTE_PATH.replace(redacted, REDACTED_PATH)
        redacted = UNIX_ABSOLUTE_PATH.replace(redacted, REDACTED_PATH)
        return redacted
    }

    private fun safeEntry(value: String?): BoundedEntry? {
        if (value == null || !isSafeEntry(value)) return null
        val bounded = truncateEntryUtf8(value, DexCompilerContract.MAX_DIAGNOSTIC_ENTRY_BYTES)
        if (!isSafeEntry(bounded.text)) return null
        return bounded
    }

    private fun isSafeEntry(value: String): Boolean =
        value.isNotBlank() &&
            !value.startsWith('/') &&
            !value.endsWith('/') &&
            '\\' !in value &&
            ':' !in value &&
            value.split('/').none { it.isEmpty() || it == "." || it == ".." } &&
            value.codePoints().noneMatch { Character.isISOControl(it) } &&
            Normalizer.normalize(value, Normalizer.Form.NFC) == value

    private fun safePosition(value: Position?): DexCompilerDiagnosticPosition? = when (value) {
        null, Position.UNKNOWN -> null
        is TextPosition -> value.toDiagnosticPosition().takeIf { it.hasValue() }
        is TextRange -> {
            val start = runCatching { value.start }.getOrNull()
            val end = runCatching { value.end }.getOrNull()
            val startValue = start?.toDiagnosticPosition()
            val endValue = end?.toDiagnosticPosition()
            DexCompilerDiagnosticPosition(
                line = startValue?.line,
                column = startValue?.column,
                offset = startValue?.offset,
                endLine = endValue?.line,
                endColumn = endValue?.column,
                endOffset = endValue?.offset,
            ).takeIf { it.hasValue() && it.isOrderedRange() }
        }
        is MethodPosition -> safePosition(runCatching { value.textPosition }.getOrNull())
        else -> null
    }

    private fun TextPosition.toDiagnosticPosition(): DexCompilerDiagnosticPosition =
        DexCompilerDiagnosticPosition(
            line = runCatching { line }.getOrNull()?.takeIf { it > 0 },
            column = runCatching { column }.getOrNull()?.takeIf { it > 0 },
            offset = runCatching { offset }.getOrNull()?.takeIf { it >= 0L },
        )

    private fun DexCompilerDiagnosticPosition.hasValue(): Boolean =
        line != null || column != null || offset != null ||
            endLine != null || endColumn != null || endOffset != null

    private fun DexCompilerDiagnosticPosition.isOrderedRange(): Boolean {
        val startOffset = offset
        val finishOffset = endOffset
        if (startOffset != null && finishOffset != null && finishOffset < startOffset) return false
        val startLine = line
        val finishLine = endLine
        if (startLine != null && finishLine != null) {
            if (finishLine < startLine) return false
            val startColumn = column
            val finishColumn = endColumn
            if (
                finishLine == startLine &&
                startColumn != null &&
                finishColumn != null &&
                finishColumn < startColumn
            ) {
                return false
            }
        }
        return true
    }

    private fun truncateEntryUtf8(value: String, maximumBytes: Int): BoundedEntry {
        var index = 0
        var bytes = 0
        while (index < value.length) {
            val codePoint = value.codePointAt(index)
            val encodedBytes = String(Character.toChars(codePoint)).toByteArray(Charsets.UTF_8).size
            if (encodedBytes > maximumBytes - bytes) break
            bytes += encodedBytes
            index += Character.charCount(codePoint)
        }
        return BoundedEntry(value.substring(0, index), index < value.length)
    }

    private data class BoundedEntry(
        val text: String,
        val truncated: Boolean,
    )

    companion object {
        val NONE = D8DiagnosticOriginResolver(emptyMap(), emptyList())

        fun create(
            programJar: File,
            classpathJars: List<File>,
            runtimeLibraries: List<File>,
            outputDirectory: File,
        ): D8DiagnosticOriginResolver {
            val labeledFiles = buildList {
                add(programJar to "program")
                classpathJars.forEachIndexed { index, file -> add(file to "classpath:$index") }
                runtimeLibraries.forEachIndexed { index, file -> add(file to "runtime-library:$index") }
                add(outputDirectory to "output")
            }
            val labels = LinkedHashMap<String, String>()
            val redactions = LinkedHashMap<String, String>()
            labeledFiles.forEach { (file, label) ->
                filePathVariants(file).forEach { path ->
                    labels[pathKey(path)] = label
                    pathTextVariants(path, file).forEach { text ->
                        if (text.isNotBlank()) redactions[text] = label
                    }
                }
            }
            return D8DiagnosticOriginResolver(
                labelsByPath = labels,
                exactRedactions = redactions.entries
                    .sortedByDescending { it.key.length }
                    .map { it.key to it.value },
            )
        }

        private fun filePathVariants(file: File): Set<String> = buildSet {
            runCatching { add(file.path) }
            runCatching { add(file.absolutePath) }
            runCatching { add(file.canonicalPath) }
        }

        private fun pathTextVariants(path: String, file: File): Set<String> = buildSet {
            add(path)
            add(path.replace('\\', '/'))
            runCatching { add(file.toURI().toString()) }
        }

        private fun pathKey(path: String): String {
            val normalized = path.replace('\\', '/')
            return if (WINDOWS_PATHS) normalized.lowercase(Locale.ROOT) else normalized
        }

        private const val MAX_ORIGIN_DEPTH = 16
        private const val UNKNOWN_ORIGIN = "unknown"
        private const val REDACTED_PATH = "<redacted-path>"
        private val WINDOWS_PATHS = File.separatorChar == '\\'
        private val FILE_URI = Regex("(?i)file:(?:/{1,3})[^\\s,;)}\\]]+")
        private val WINDOWS_ABSOLUTE_PATH = Regex(
            "(?i)(?<![a-z0-9_])(?:[a-z]:[\\\\/]|\\\\\\\\)[^\\s,;)}\\]]+",
        )
        private val UNIX_ABSOLUTE_PATH = Regex(
            "(?<![a-zA-Z0-9_:/])/(?!/)(?:[^/\\s,;)}\\]]+/)*[^/\\s,;)}\\]]+",
        )
    }
}

internal data class D8DiagnosticMetadata(
    val origin: String? = null,
    val entry: String? = null,
    val position: DexCompilerDiagnosticPosition? = null,
    val truncated: Boolean = false,
)

internal fun immutableDiagnostics(
    values: Collection<DexCompilerDiagnostic>,
): List<DexCompilerDiagnostic> = Collections.unmodifiableList(ArrayList(values))
