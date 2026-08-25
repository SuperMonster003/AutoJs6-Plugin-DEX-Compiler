package io.github.supermonster003.autojs6.plugin.dexcompiler

import com.android.tools.r8.CompilationMode
import com.android.tools.r8.D8
import com.android.tools.r8.D8Command
import com.android.tools.r8.Diagnostic
import com.android.tools.r8.DiagnosticsHandler
import com.android.tools.r8.OutputMode
import com.android.tools.r8.Version
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.google.gson.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import javax.tools.DiagnosticCollector
import javax.tools.JavaFileObject
import javax.tools.ToolProvider

class D8UpgradeMatrixTest {
    @Test
    fun manifestIsCompleteAndExpandsToExactlySixtyUniqueCells() {
        val manifestJson = String(Files.readAllBytes(manifestPath()), StandardCharsets.UTF_8)
        val root = GSON.fromJson(manifestJson, JsonObject::class.java)
        assertEquals(MANIFEST_KEYS, root.keySet())
        assertEquals(COMPILER_KEYS, root.getAsJsonObject("compiler").keySet())
        root.getAsJsonArray("cases").forEach { caseElement ->
            assertEquals(CASE_KEYS, caseElement.asJsonObject.keySet())
        }

        val manifest = GSON.fromJson(manifestJson, MatrixManifest::class.java)
        assertEquals(MATRIX_SCHEMA_VERSION, manifest.schemaVersion)
        assertEquals(MATRIX_ID, manifest.matrixId)
        assertEquals(COMPILER_COORDINATE, manifest.compiler.coordinate)
        assertEquals(PINNED_COMPILER_VERSION, manifest.compiler.pinnedVersion)
        assertEquals(ROLLBACK_COMPILER_VERSION, manifest.compiler.rollbackVersion)
        assertEquals(CANDIDATE_VERSION_PROPERTY, manifest.compiler.candidateVersionProperty)
        assertEquals(ROLLBACK_EVALUATION_PROPERTY_NAME, manifest.compiler.rollbackEvaluationProperty)
        assertEquals(EVIDENCE_BOUNDARY, manifest.evidenceBoundary)
        assertEquals(ACCEPTANCE_KEY_TEMPLATE, manifest.acceptanceKeyTemplate)
        assertEquals((24..36).toList(), manifest.minApis)
        assertEquals(listOf("DEBUG", "RELEASE"), manifest.modes)
        assertEquals(EXPECTED_CASE_IDS, manifest.cases.map { it.id })
        assertEquals(EXPECTED_CASES, manifest.cases.associateBy { it.id })

        val cells = manifest.cells()
        assertEquals(EXPECTED_CELL_COUNT, cells.size)
        assertEquals(EXPECTED_CELL_COUNT, cells.map { it.cellId }.toSet().size)
        assertEquals(EXPECTED_CELL_COUNT, cells.map { it.acceptanceKey(PINNED_COMPILER_VERSION) }.toSet().size)
    }

    @Test
    fun selectedCompilerVersionHasOneRuntimeTruth() {
        val declaredVersion = requiredProperty(DECLARED_VERSION_PROPERTY)
        val pinnedVersion = requiredProperty(PINNED_VERSION_PROPERTY)
        val candidateEvaluation = when (requiredProperty(CANDIDATE_EVALUATION_PROPERTY)) {
            "true" -> true
            "false" -> false
            else -> throw AssertionError("Candidate evaluation property must be exactly true or false")
        }
        val rollbackEvaluation = when (requiredProperty(ROLLBACK_EVALUATION_PROPERTY)) {
            "true" -> true
            "false" -> false
            else -> throw AssertionError("Rollback evaluation property must be exactly true or false")
        }
        assertFalse("Candidate and rollback evaluation are mutually exclusive", candidateEvaluation && rollbackEvaluation)
        val manifest = readManifest()
        val runtimeVersion = runtimeD8Version()
        assertEquals(declaredVersion, runtimeVersion)
        assertEquals(declaredVersion, DexCompilerRuntime.COMPILER_VERSION)
        assertEquals(declaredVersion, BuildConfig.D8_COMPILER_VERSION)
        if (candidateEvaluation) {
            assertEquals(manifest.compiler.pinnedVersion, pinnedVersion)
            assertTrue("A candidate override must differ from the pinned baseline", declaredVersion != pinnedVersion)
        } else if (rollbackEvaluation) {
            assertEquals(manifest.compiler.rollbackVersion, pinnedVersion)
            assertEquals("A rollback observation must use the catalog-pinned old version", pinnedVersion, declaredVersion)
        } else {
            assertEquals(manifest.compiler.pinnedVersion, pinnedVersion)
            assertEquals("A default observation must use the catalog-pinned version", pinnedVersion, declaredVersion)
        }
    }

    @Test
    fun kotlinFixtureUsesDeclaredCurrentCompilerAndJvmTargetTwentyOne() {
        val kotlinCompilerVersion = requiredProperty(KOTLIN_COMPILER_VERSION_PROPERTY)
        assertTrue(kotlinCompilerVersion.matches(Regex("^[0-9][0-9A-Za-z.+_-]{0,63}$")))
        val bytes = kotlinFixtureBytes()
        assertEquals(JAVA_21_CLASSFILE_MAJOR, classFileMajorVersion(bytes))
        assertTrue(
            "The fixture must retain Kotlin metadata emitted by the current compiler",
            bytes.toString(Charsets.ISO_8859_1).contains("kotlin/Metadata"),
        )
    }

    @Test
    fun realD8CompilerMatrixWritesOneStrictReportPerCell() {
        val manifest = readManifest()
        val declaredVersion = requiredProperty(DECLARED_VERSION_PROPERTY)
        val producerInvocationId = requiredProperty(PRODUCER_INVOCATION_ID_PROPERTY)
        assertEquals(producerInvocationId, UUID.fromString(producerInvocationId).toString())
        assertEquals(declaredVersion, runtimeD8Version())
        val androidJar = androidJarPath()
        val runtimeFingerprint = FileFingerprint.from(androidJar)
        val reportDirectory = prepareReportDirectory()
        val workspace = Files.createTempDirectory("r4-d8-upgrade-matrix")
        val failures = mutableListOf<String>()
        try {
            val fixtures = FixtureFactory(workspace).createAll(manifest.cases)
            manifest.cells().forEachIndexed { index, cell ->
                val fixture = requireNotNull(fixtures[cell.caseId])
                val observation = observe(cell, fixture, androidJar, workspace)
                val report = buildReport(
                    manifest = manifest,
                    cell = cell,
                    fixture = fixture,
                    runtimeFingerprint = runtimeFingerprint,
                    declaredVersion = declaredVersion,
                    producerInvocationId = producerInvocationId,
                    observationSequence = index + 1,
                    observation = observation,
                )
                writeReport(reportDirectory.resolve("${cell.cellId}.json"), report)

                if (observation.observedOutcome != cell.expectedOutcome) {
                    failures += "${cell.cellId}: expected ${cell.expectedOutcome}, observed ${observation.observedOutcome} (${observation.summary})"
                }
                if (cell.fixtureKind == "GENERATED_MULTIDEX" && observation.observedOutcome == COMPILE_SUCCESS) {
                    val names = observation.output?.dexEntries?.map { it.entryName }.orEmpty()
                    if (!names.containsAll(listOf("classes.dex", "classes2.dex"))) {
                        failures += "${cell.cellId}: generated fixture did not produce classes.dex and classes2.dex; found $names"
                    }
                }
            }

            val reports = Files.list(reportDirectory).use { stream ->
                stream.filter { it.fileName.toString().endsWith(".json") }.toList()
            }
            assertEquals(EXPECTED_CELL_COUNT, reports.size)
            val persistedReports = reports.joinToString("\n") { reportPath ->
                String(Files.readAllBytes(reportPath), StandardCharsets.UTF_8)
            }
            assertFalse(
                "Matrix reports must not persist the private temporary workspace path",
                persistedReports.contains(workspace.toAbsolutePath().normalize().toString(), ignoreCase = true),
            )
            assertFalse(
                "Matrix reports must not persist Windows temporary-profile paths",
                persistedReports.contains("AppData\\Local\\Temp", ignoreCase = true) ||
                    persistedReports.contains("AppData/Local/Temp", ignoreCase = true),
            )
            assertFalse(
                "Matrix reports must not persist Unix temporary workspace paths",
                Regex("/(?:private/)?tmp/r4-d8-upgrade-matrix", RegexOption.IGNORE_CASE).containsMatchIn(persistedReports),
            )
            assertFalse(
                "Matrix reports must not persist Unix absolute paths",
                UNIX_ABSOLUTE_PATH.containsMatchIn(persistedReports),
            )
            assertTrue(failures.joinToString(separator = "\n"), failures.isEmpty())
        } finally {
            workspace.toFile().deleteRecursively()
        }
    }

    private fun observe(
        cell: MatrixCell,
        fixture: Fixture,
        androidJar: Path,
        workspace: Path,
    ): CellObservation {
        val expectedSuccess = cell.expectedOutcome == COMPILE_SUCCESS
        val runCount = if (expectedSuccess) 2 else 1
        val runs = (1..runCount).map { runNumber ->
            runD8(
                cell = cell,
                fixture = fixture,
                androidJar = androidJar,
                outputDirectory = workspace.resolve("runs").resolve(cell.cellId).resolve("run-$runNumber"),
            )
        }
        val allSucceeded = runs.all { it.success }
        val observedOutcome = if (allSucceeded) COMPILE_SUCCESS else COMPILE_FAILURE
        val producedOutput = if (allSucceeded) runs.first().output else null
        val identicalDigest = when {
            runCount < 2 -> null
            !allSucceeded -> false
            else -> runs[0].output?.sha256 == runs[1].output?.sha256
        }
        val diagnosticSummary = runs
            .filterNot { it.success }
            .joinToString(" | ") { it.summary }
            .ifBlank { "D8 completed without an error diagnostic." }
        val summary = when {
            allSucceeded && runCount == 2 ->
                "D8 completed both required JVM compiler observations; output digests identical=$identicalDigest."
            allSucceeded -> "D8 completed the single required JVM compiler observation."
            else -> "D8 rejected at least one required JVM compiler observation: $diagnosticSummary"
        }.boundedSummary()
        return CellObservation(
            observedOutcome = observedOutcome,
            output = producedOutput,
            runCount = runCount,
            identicalOutputDigest = identicalDigest,
            summary = summary,
        )
    }

    private fun runD8(
        cell: MatrixCell,
        fixture: Fixture,
        androidJar: Path,
        outputDirectory: Path,
    ): D8Run {
        Files.createDirectories(outputDirectory)
        val diagnostics = CapturingDiagnostics()
        return try {
            val builder = D8Command.builder(diagnostics)
                .addProgramFiles(fixture.programFiles)
                .addLibraryFiles(androidJar)
                .setMinApiLevel(cell.minApi)
                .setMode(cell.mode.toCompilationMode())
                .setOutput(outputDirectory, OutputMode.DexIndexed)
            fixture.classpathFiles.forEach { builder.addClasspathFiles(it) }
            D8.run(builder.build())
            if (cell.fixtureKind == "MISSING_DEPENDENCY") {
                val retainedReference = Files.list(outputDirectory).use { stream ->
                    stream.filter { Files.isRegularFile(it) && DEX_ENTRY_PATTERN.matches(it.fileName.toString()) }
                        .toList()
                        .any { dexPath ->
                            Files.readAllBytes(dexPath).toString(Charsets.ISO_8859_1)
                                .contains(MISSING_DEPENDENCY_DESCRIPTOR)
                        }
                }
                check(retainedReference) {
                    "D8 output did not retain the unresolved dependency descriptor"
                }
            }
            val output = ProducedOutput.from(outputDirectory)
            D8Run(
                success = true,
                output = output,
                summary = "D8 produced ${output.dexEntries.size} indexed DEX file(s).",
            )
        } catch (error: Exception) {
            val privateRoots = fixture.privateRoots() + listOf(
                outputDirectory.toAbsolutePath().normalize().toString(),
                androidJar.toAbsolutePath().normalize().toString(),
            )
            D8Run(
                success = false,
                output = null,
                summary = diagnostics.failureSummary(error, privateRoots).boundedSummary(),
            )
        }
    }

    private fun buildReport(
        manifest: MatrixManifest,
        cell: MatrixCell,
        fixture: Fixture,
        runtimeFingerprint: FileFingerprint,
        declaredVersion: String,
        producerInvocationId: String,
        observationSequence: Int,
        observation: CellObservation,
    ): Map<String, Any?> {
        val matchesExpectation = observation.observedOutcome == cell.expectedOutcome
        val output = observation.output
        val outputValue = if (observation.observedOutcome == COMPILE_SUCCESS && output != null) {
            linkedMapOf<String, Any?>(
                "status" to "PRODUCED",
                "sha256" to output.sha256,
                "dexManifest" to output.dexEntries.map { entry ->
                    linkedMapOf(
                        "entryName" to entry.entryName,
                        "sha256" to entry.sha256,
                        "byteLength" to entry.byteLength,
                    )
                },
                "summary" to "Accepted indexed DEX output contains ${output.dexEntries.size} file(s) and ${output.byteLength} bytes.",
            )
        } else {
            linkedMapOf<String, Any?>(
                "status" to "NOT_PRODUCED",
                "sha256" to null,
                "dexManifest" to emptyList<Any>(),
                "summary" to "No compiler output was accepted for this failed observation.",
            )
        }
        val repeatObservation = if (observation.runCount >= 2) {
            linkedMapOf<String, Any?>(
                "attempted" to true,
                "runCount" to observation.runCount,
                "identicalOutputDigest" to observation.identicalOutputDigest,
                "summary" to if (observation.output == null) {
                    "Both required attempts ran, but at least one did not produce accepted output; digest equality is false."
                } else {
                    "Two successful observations had identical output digest=${observation.identicalOutputDigest}; no determinism claim is made."
                },
            )
        } else {
            linkedMapOf<String, Any?>(
                "attempted" to false,
                "runCount" to 1,
                "identicalOutputDigest" to null,
                "summary" to "Known-failure cell was observed once; repeat comparison was not attempted.",
            )
        }
        return linkedMapOf(
            "schemaVersion" to REPORT_SCHEMA_VERSION,
            "matrixId" to manifest.matrixId,
            "reportId" to UUID.randomUUID().toString(),
            "producerInvocationId" to producerInvocationId,
            "observationSequence" to observationSequence,
            "recordedAtUtc" to Instant.now().toString(),
            "cellId" to cell.cellId,
            "acceptanceKey" to cell.acceptanceKey(declaredVersion),
            "caseId" to cell.caseId,
            "minApi" to cell.minApi,
            "mode" to cell.mode,
            "evidenceBoundary" to manifest.evidenceBoundary,
            "compiler" to linkedMapOf(
                "coordinate" to manifest.compiler.coordinate,
                "version" to declaredVersion,
                "candidateVersionProperty" to manifest.compiler.candidateVersionProperty,
            ),
            "input" to linkedMapOf(
                "sha256" to fixture.sha256,
                "summary" to fixture.summary,
            ),
            "runtimeFingerprint" to linkedMapOf(
                "sha256" to runtimeFingerprint.sha256,
                "summary" to "android.jar byteLength=${runtimeFingerprint.byteLength}; SHA-256 identifies the exact D8 runtime library input.",
            ),
            "observedCompilerOutcome" to observation.observedOutcome,
            "output" to outputValue,
            "outcome" to if (matchesExpectation) "PASS" else "FAIL",
            "behaviorDelta" to linkedMapOf(
                "classification" to if (matchesExpectation) "NONE" else "UNEXPECTED",
                "summary" to if (matchesExpectation) {
                    "Observed compiler outcome matches the manifest expectation."
                } else {
                    "Observed compiler outcome differs from the manifest expectation."
                },
            ),
            "repeatObservation" to repeatObservation,
            "determinismClaim" to "NOT_CLAIMED",
            "summary" to "${cell.cellId} observed ${observation.observedOutcome}; expected ${cell.expectedOutcome}. ${observation.summary}".boundedSummary(),
        )
    }

    private fun writeReport(path: Path, report: Map<String, Any?>) {
        val temporary = path.resolveSibling("${path.fileName}.tmp")
        Files.write(
            temporary,
            (REPORT_GSON.toJson(report) + "\n").toByteArray(StandardCharsets.UTF_8),
        )
        try {
            Files.move(temporary, path, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } catch (_: AtomicMoveNotSupportedException) {
            Files.move(temporary, path, StandardCopyOption.REPLACE_EXISTING)
        }
    }

    private fun readManifest(): MatrixManifest = GSON.fromJson(
        String(Files.readAllBytes(manifestPath()), StandardCharsets.UTF_8),
        MatrixManifest::class.java,
    )

    private fun manifestPath(): Path {
        val path = Path.of(requiredProperty(MANIFEST_PATH_PROPERTY)).toAbsolutePath().normalize()
        assertTrue("Matrix manifest must be a regular file: $path", Files.isRegularFile(path))
        return path
    }

    private fun androidJarPath(): Path {
        val path = Path.of(requiredProperty(ANDROID_JAR_PROPERTY)).toAbsolutePath().normalize()
        assertTrue("android.jar must be a regular file: $path", Files.isRegularFile(path))
        assertEquals("android.jar", path.fileName.toString())
        return path
    }

    private fun prepareReportDirectory(): Path {
        val path = Path.of(requiredProperty(REPORT_DIRECTORY_PROPERTY)).toAbsolutePath().normalize()
        assertTrue("Refusing a filesystem-root report directory: $path", path.parent != null)
        Files.createDirectories(path)
        val existingJson = Files.list(path).use { stream ->
            stream.filter { Files.isRegularFile(it) && it.fileName.toString().endsWith(".json") }.toList()
        }
        val nonPassingCellReports = existingJson
            .filterNot { it.fileName.toString() == "gate.json" }
            .filter { reportPath ->
                runCatching {
                    val json = GSON.fromJson(
                        String(Files.readAllBytes(reportPath), StandardCharsets.UTF_8),
                        JsonObject::class.java,
                    )
                    json.get("outcome")?.asString == "PASS"
                }.getOrDefault(false).not()
            }
        assertTrue(
            "Refusing to overwrite prior FAIL or unreadable matrix evidence; archive first: $nonPassingCellReports",
            nonPassingCellReports.isEmpty(),
        )
        existingJson.forEach { reportPath ->
            Files.delete(reportPath)
        }
        return path
    }

    private fun requiredProperty(name: String): String =
        System.getProperty(name)?.takeIf { it.isNotBlank() }
            ?: throw AssertionError("Required JVM system property is missing: $name")

    private class FixtureFactory(private val root: Path) {
        private val javac = requireNotNull(ToolProvider.getSystemJavaCompiler()) {
            "The R4 compiler matrix requires a full JDK with ToolProvider javac"
        }

        fun createAll(cases: List<MatrixCase>): Map<String, Fixture> = cases.associate { matrixCase ->
            matrixCase.id to create(matrixCase)
        }

        private fun create(matrixCase: MatrixCase): Fixture = when (matrixCase.fixtureKind) {
            "JAVA_CLASSFILE" -> javaFixture(matrixCase)
            "KOTLIN_CLASSFILE" -> kotlinFixture(matrixCase)
            "STANDARD_DESUGARING" -> standardDesugaringFixture(matrixCase)
            "GENERATED_MULTIDEX" -> generatedMultidexFixture(matrixCase)
            "MISSING_DEPENDENCY" -> missingDependencyFixture(matrixCase)
            "MALFORMED_CLASSFILE" -> malformedFixture(matrixCase)
            "UNSUPPORTED_CLASSFILE" -> unsupportedFixture(matrixCase)
            "DUPLICATE_DEFINITION" -> duplicateDefinitionFixture(matrixCase)
            else -> error("Unsupported fixture kind: ${matrixCase.fixtureKind}")
        }

        private fun javaFixture(matrixCase: MatrixCase): Fixture {
            val fixtureRoot = root.resolve("fixtures").resolve(matrixCase.id)
            val className = "Java${matrixCase.languageVersion}Fixture"
            val packageName = "fixture.java${matrixCase.languageVersion}"
            val classes = compileJava(
                fixtureRoot = fixtureRoot,
                release = matrixCase.languageVersion,
                sources = mapOf(
                    "$packageName.$className" to """
                        package $packageName;
                        public final class $className {
                            public static int answer() { return ${matrixCase.languageVersion}; }
                        }
                    """.trimIndent(),
                ),
            )
            val classFile = classes.resolve(packageName.replace('.', '/')).resolve("$className.class")
            assertEquals(
                44 + matrixCase.languageVersion.toInt(),
                classFileMajorVersion(Files.readAllBytes(classFile)),
            )
            val jar = fixtureRoot.resolve("${matrixCase.id}.jar")
            writeStoredJar(jar, classEntries(classes))
            return Fixture.from(
                programFiles = listOf(jar),
                summary = "ToolProvider javac --release ${matrixCase.languageVersion} emitted JVM target ${matrixCase.jvmTarget} classfiles.",
            )
        }

        private fun kotlinFixture(matrixCase: MatrixCase): Fixture {
            val bytes = kotlinFixtureBytes()
            assertEquals(JAVA_21_CLASSFILE_MAJOR, classFileMajorVersion(bytes))
            val fixtureRoot = root.resolve("fixtures").resolve(matrixCase.id)
            val jar = fixtureRoot.resolve("${matrixCase.id}.jar")
            writeStoredJar(jar, mapOf(KOTLIN_FIXTURE_RESOURCE to bytes))
            val compilerVersion = requiredSystemProperty(KOTLIN_COMPILER_VERSION_PROPERTY)
            return Fixture.from(
                programFiles = listOf(jar),
                summary = "Kotlin compiler $compilerVersion emitted the checked current fixture at JVM target ${matrixCase.jvmTarget}.",
            )
        }

        private fun standardDesugaringFixture(matrixCase: MatrixCase): Fixture {
            val fixtureRoot = root.resolve("fixtures").resolve(matrixCase.id)
            val classes = compileJava(
                fixtureRoot = fixtureRoot,
                release = matrixCase.languageVersion,
                sources = mapOf(
                    "fixture.desugar.Greeter" to """
                        package fixture.desugar;
                        public interface Greeter {
                            default String greet(String name) { return "hello " + name; }
                        }
                    """.trimIndent(),
                    "fixture.desugar.StandardDesugaringFixture" to """
                        package fixture.desugar;
                        import java.util.function.Supplier;
                        public final class StandardDesugaringFixture implements Greeter {
                            public Supplier<String> supplier() { return () -> greet("matrix"); }
                        }
                    """.trimIndent(),
                ),
            )
            val jar = fixtureRoot.resolve("${matrixCase.id}.jar")
            writeStoredJar(jar, classEntries(classes))
            return Fixture.from(
                programFiles = listOf(jar),
                summary = "ToolProvider javac --release ${matrixCase.languageVersion} emitted a default-interface and lambda desugaring fixture.",
            )
        }

        private fun generatedMultidexFixture(matrixCase: MatrixCase): Fixture {
            val fixtureRoot = root.resolve("fixtures").resolve(matrixCase.id)
            val sources = linkedMapOf<String, String>()
            repeat(MULTIDEX_CLASS_COUNT) { classIndex ->
                val simpleName = "Generated${classIndex.toString().padStart(3, '0')}"
                val source = buildString {
                    append("package fixture.multidex; public final class ").append(simpleName).append(" {")
                    repeat(MULTIDEX_METHODS_PER_CLASS) { methodIndex ->
                        append(" public static int m")
                            .append(methodIndex.toString().padStart(4, '0'))
                            .append("() { return ")
                            .append(methodIndex)
                            .append("; }")
                    }
                    append(" }")
                }
                sources["fixture.multidex.$simpleName"] = source
            }
            val classes = compileJava(
                fixtureRoot = fixtureRoot,
                release = matrixCase.languageVersion,
                sources = sources,
            )
            val jar = fixtureRoot.resolve("${matrixCase.id}.jar")
            writeStoredJar(jar, classEntries(classes))
            val declaredMethods = MULTIDEX_CLASS_COUNT * (MULTIDEX_METHODS_PER_CLASS + 1)
            assertTrue(declaredMethods > DEX_METHOD_ID_LIMIT)
            return Fixture.from(
                programFiles = listOf(jar),
                summary = "Generated $MULTIDEX_CLASS_COUNT Java classes with $declaredMethods declared methods via javac --release ${matrixCase.languageVersion}; no binary corpus is checked in.",
            )
        }

        private fun missingDependencyFixture(matrixCase: MatrixCase): Fixture {
            val fixtureRoot = root.resolve("fixtures").resolve(matrixCase.id)
            val classes = compileJava(
                fixtureRoot = fixtureRoot,
                release = matrixCase.languageVersion,
                sources = mapOf(
                    "fixture.missing.MissingDependency" to """
                        package fixture.missing;
                        public final class MissingDependency {
                            public static int value() { return 41; }
                        }
                    """.trimIndent(),
                    "fixture.missing.MissingDependencyUser" to """
                        package fixture.missing;
                        public final class MissingDependencyUser {
                            public static int answer() { return MissingDependency.value() + 1; }
                        }
                    """.trimIndent(),
                ),
            )
            val programJar = fixtureRoot.resolve("${matrixCase.id}-program.jar")
            writeStoredJar(
                programJar,
                mapOf(
                    "fixture/missing/MissingDependencyUser.class" to
                        Files.readAllBytes(classes.resolve("fixture/missing/MissingDependencyUser.class")),
                ),
            )
            return Fixture.from(
                programFiles = listOf(programJar),
                summary = "Program references an omitted MissingDependency type; the matrix records D8 compile-time behavior without claiming runtime resolution.",
            )
        }

        private fun malformedFixture(matrixCase: MatrixCase): Fixture {
            val fixtureRoot = root.resolve("fixtures").resolve(matrixCase.id)
            val jar = fixtureRoot.resolve("${matrixCase.id}.jar")
            writeStoredJar(
                jar,
                mapOf(
                    "fixture/malformed/Malformed.class" to byteArrayOf(
                        0xca.toByte(), 0xfe.toByte(), 0xba.toByte(), 0xbe.toByte(),
                        0x00, 0x00, 0x00, JAVA_21_CLASSFILE_MAJOR.toByte(), 0x00, 0x01,
                    ),
                ),
            )
            return Fixture.from(
                programFiles = listOf(jar),
                summary = "Stored JAR contains a deliberately truncated classfile with the standard CAFEBABE header.",
            )
        }

        private fun unsupportedFixture(matrixCase: MatrixCase): Fixture {
            val fixtureRoot = root.resolve("fixtures").resolve(matrixCase.id)
            val classes = compileJava(
                fixtureRoot = fixtureRoot,
                release = "21",
                sources = mapOf(
                    "fixture.unsupported.UnsupportedClassfile" to
                        "package fixture.unsupported; public final class UnsupportedClassfile {}",
                ),
            )
            val bytes = Files.readAllBytes(classes.resolve("fixture/unsupported/UnsupportedClassfile.class"))
            bytes[6] = 0x7f
            bytes[7] = 0xff.toByte()
            val jar = fixtureRoot.resolve("${matrixCase.id}.jar")
            writeStoredJar(jar, mapOf("fixture/unsupported/UnsupportedClassfile.class" to bytes))
            return Fixture.from(
                programFiles = listOf(jar),
                summary = "Valid javac classfile framing was changed to unsupported major version 32767.",
            )
        }

        private fun duplicateDefinitionFixture(matrixCase: MatrixCase): Fixture {
            val fixtureRoot = root.resolve("fixtures").resolve(matrixCase.id)
            val classes = compileJava(
                fixtureRoot = fixtureRoot,
                release = matrixCase.languageVersion,
                sources = mapOf(
                    "fixture.duplicate.DuplicateDefinition" to
                        "package fixture.duplicate; public final class DuplicateDefinition { public static int value() { return 1; } }",
                ),
            )
            val entry = "fixture/duplicate/DuplicateDefinition.class"
            val bytes = Files.readAllBytes(classes.resolve(entry))
            val first = fixtureRoot.resolve("duplicate-a.jar")
            val second = fixtureRoot.resolve("duplicate-b.jar")
            writeStoredJar(first, mapOf(entry to bytes))
            writeStoredJar(second, mapOf(entry to bytes))
            return Fixture.from(
                programFiles = listOf(first, second),
                summary = "Two program archives contain the same class descriptor and require D8 duplicate-definition rejection.",
            )
        }

        private fun compileJava(
            fixtureRoot: Path,
            release: String,
            sources: Map<String, String>,
        ): Path {
            val sourceRoot = fixtureRoot.resolve("sources")
            val classes = fixtureRoot.resolve("classes")
            Files.createDirectories(sourceRoot)
            Files.createDirectories(classes)
            val sourceFiles = sources.map { (qualifiedName, source) ->
                val path = sourceRoot.resolve(qualifiedName.replace('.', '/') + ".java")
                Files.createDirectories(path.parent)
                Files.write(path, source.toByteArray(StandardCharsets.UTF_8))
                path.toFile()
            }
            val diagnostics = DiagnosticCollector<JavaFileObject>()
            javac.getStandardFileManager(diagnostics, null, StandardCharsets.UTF_8).use { fileManager ->
                val units = fileManager.getJavaFileObjectsFromFiles(sourceFiles)
                val success = javac.getTask(
                    null,
                    fileManager,
                    diagnostics,
                    listOf("--release", release, "-encoding", "UTF-8", "-g:none", "-d", classes.toString()),
                    null,
                    units,
                ).call()
                assertTrue(
                    "javac --release $release failed: ${diagnostics.diagnostics.joinToString { it.getMessage(null) }}",
                    success,
                )
            }
            return classes
        }
    }

    private class CapturingDiagnostics : DiagnosticsHandler {
        private val errors = mutableListOf<String>()

        override fun error(diagnostic: Diagnostic) {
            if (errors.size < MAX_CAPTURED_DIAGNOSTICS) errors += diagnostic.diagnosticMessage
        }

        override fun warning(diagnostic: Diagnostic) = Unit

        override fun info(diagnostic: Diagnostic) = Unit

        fun failureSummary(error: Exception, privateRoots: List<String>): String {
            val message = errors.firstOrNull().orEmpty().ifBlank {
                error.message ?: "No D8 diagnostic message was available."
            }
            return "${error.javaClass.simpleName}: ${message.redactPrivatePaths(privateRoots)}"
        }
    }

    private data class MatrixManifest(
        val schemaVersion: String,
        val matrixId: String,
        val compiler: MatrixCompiler,
        val evidenceBoundary: String,
        val acceptanceKeyTemplate: String,
        val minApis: List<Int>,
        val modes: List<String>,
        val cases: List<MatrixCase>,
    ) {
        fun cells(): List<MatrixCell> = cases.flatMap { matrixCase ->
            matrixCase.minApis.flatMap { minApi ->
                matrixCase.modes.map { mode ->
                    MatrixCell(
                        caseId = matrixCase.id,
                        fixtureKind = matrixCase.fixtureKind,
                        languageVersion = matrixCase.languageVersion,
                        jvmTarget = matrixCase.jvmTarget,
                        minApi = minApi,
                        mode = mode,
                        expectedOutcome = matrixCase.expectedOutcome,
                    )
                }
            }
        }
    }

    private data class MatrixCompiler(
        val coordinate: String,
        val pinnedVersion: String,
        val rollbackVersion: String,
        val candidateVersionProperty: String,
        val rollbackEvaluationProperty: String,
    )

    private data class MatrixCase(
        val id: String,
        val fixtureKind: String,
        val languageVersion: String,
        val jvmTarget: String,
        val minApis: List<Int>,
        val modes: List<String>,
        val expectedOutcome: String,
    )

    private data class MatrixCell(
        val caseId: String,
        val fixtureKind: String,
        val languageVersion: String,
        val jvmTarget: String,
        val minApi: Int,
        val mode: String,
        val expectedOutcome: String,
    ) {
        val cellId: String = "$caseId--api$minApi--${mode.lowercase()}"

        fun acceptanceKey(compilerVersion: String): String =
            "$caseId|minApi=$minApi|mode=$mode|compiler=$compilerVersion"
    }

    private data class Fixture(
        val programFiles: List<Path>,
        val classpathFiles: List<Path>,
        val sha256: String,
        val summary: String,
    ) {
        fun privateRoots(): List<String> = (programFiles + classpathFiles)
            .mapNotNull { it.toAbsolutePath().normalize().parent?.toString() }
            .distinct()
            .sortedByDescending { it.length }

        companion object {
            fun from(
                programFiles: List<Path>,
                classpathFiles: List<Path> = emptyList(),
                summary: String,
            ): Fixture {
                assertTrue(programFiles.isNotEmpty())
                programFiles.forEach { assertTrue("Missing program input: $it", Files.isRegularFile(it)) }
                return Fixture(
                    programFiles = programFiles,
                    classpathFiles = classpathFiles,
                    sha256 = digestFixture(programFiles, classpathFiles),
                    summary = summary.boundedSummary(),
                )
            }
        }
    }

    private data class D8Run(
        val success: Boolean,
        val output: ProducedOutput?,
        val summary: String,
    )

    private data class CellObservation(
        val observedOutcome: String,
        val output: ProducedOutput?,
        val runCount: Int,
        val identicalOutputDigest: Boolean?,
        val summary: String,
    )

    private data class ProducedOutput(
        val sha256: String,
        val dexEntries: List<DexEntryFingerprint>,
        val byteLength: Long,
    ) {
        companion object {
            fun from(directory: Path): ProducedOutput {
                val dexPaths = Files.list(directory).use { stream ->
                    stream.filter { Files.isRegularFile(it) && DEX_ENTRY_PATTERN.matches(it.fileName.toString()) }
                        .sorted(compareBy<Path> { dexEntryOrdinal(it.fileName.toString()) })
                        .toList()
                }
                check(dexPaths.isNotEmpty()) { "D8 returned without indexed DEX output" }
                val entries = dexPaths.map { DexEntryFingerprint.from(it) }
                return ProducedOutput(
                    sha256 = digestNamedFiles(dexPaths),
                    dexEntries = entries,
                    byteLength = entries.sumOf { it.byteLength },
                )
            }
        }
    }

    private data class DexEntryFingerprint(
        val entryName: String,
        val sha256: String,
        val byteLength: Long,
    ) {
        companion object {
            fun from(path: Path): DexEntryFingerprint = DexEntryFingerprint(
                entryName = path.fileName.toString(),
                sha256 = sha256(path),
                byteLength = Files.size(path),
            )
        }
    }

    private data class FileFingerprint(val sha256: String, val byteLength: Long) {
        companion object {
            fun from(path: Path): FileFingerprint = FileFingerprint(sha256(path), Files.size(path))
        }
    }

    private companion object {
        const val MANIFEST_PATH_PROPERTY = "d8.matrix.manifestPath"
        const val ANDROID_JAR_PROPERTY = "d8.matrix.androidJar"
        const val REPORT_DIRECTORY_PROPERTY = "d8.matrix.reportDirectory"
        const val DECLARED_VERSION_PROPERTY = "d8.matrix.declaredVersion"
        const val PINNED_VERSION_PROPERTY = "d8.matrix.pinnedVersion"
        const val CANDIDATE_EVALUATION_PROPERTY = "d8.matrix.candidateEvaluation"
        const val ROLLBACK_EVALUATION_PROPERTY = "d8.matrix.rollbackEvaluation"
        const val PRODUCER_INVOCATION_ID_PROPERTY = "d8.matrix.producerInvocationId"
        const val KOTLIN_COMPILER_VERSION_PROPERTY = "d8.matrix.kotlinCompilerVersion"
        const val MATRIX_SCHEMA_VERSION = "autojs6.dex.r4.d8-upgrade-matrix/v2"
        const val REPORT_SCHEMA_VERSION = "autojs6.dex.r4.d8-upgrade-report/v2"
        const val MATRIX_ID = "r4.1-g1-d8-upgrade"
        const val COMPILER_COORDINATE = "com.android.tools:r8"
        const val PINNED_COMPILER_VERSION = "8.13.22"
        const val ROLLBACK_COMPILER_VERSION = "8.13.17"
        const val CANDIDATE_VERSION_PROPERTY = "d8CandidateVersion"
        const val ROLLBACK_EVALUATION_PROPERTY_NAME = "d8RollbackEvaluation"
        const val EVIDENCE_BOUNDARY = "JVM_COMPILER_ONLY"
        const val ACCEPTANCE_KEY_TEMPLATE = "{caseId}|minApi={minApi}|mode={mode}|compiler={compilerVersion}"
        const val EXPECTED_CELL_COUNT = 60
        const val JAVA_21_CLASSFILE_MAJOR = 65
        const val DEX_METHOD_ID_LIMIT = 65_536
        const val MULTIDEX_CLASS_COUNT = 96
        const val MULTIDEX_METHODS_PER_CLASS = 684
        const val MAX_CAPTURED_DIAGNOSTICS = 4
        const val COMPILE_SUCCESS = "COMPILE_SUCCESS"
        const val COMPILE_FAILURE = "COMPILE_FAILURE"
        const val KOTLIN_FIXTURE_RESOURCE =
            "io/github/supermonster003/autojs6/plugin/dexcompiler/D8UpgradeKotlinFixture.class"
        const val MISSING_DEPENDENCY_DESCRIPTOR = "Lfixture/missing/MissingDependency;"

        val GSON: Gson = Gson()
        val REPORT_GSON: Gson = GsonBuilder().serializeNulls().setPrettyPrinting().create()
        val DEX_ENTRY_PATTERN = Regex("^classes(?:[2-9]|[1-9][0-9]+)?\\.dex$")
        val MANIFEST_KEYS = setOf(
            "schemaVersion",
            "matrixId",
            "compiler",
            "evidenceBoundary",
            "acceptanceKeyTemplate",
            "minApis",
            "modes",
            "cases",
        )
        val COMPILER_KEYS = setOf(
            "coordinate",
            "pinnedVersion",
            "rollbackVersion",
            "candidateVersionProperty",
            "rollbackEvaluationProperty",
        )
        val CASE_KEYS = setOf(
            "id",
            "fixtureKind",
            "languageVersion",
            "jvmTarget",
            "minApis",
            "modes",
            "expectedOutcome",
        )
        val EXPECTED_CASE_IDS = listOf(
            "java8",
            "java11",
            "java17",
            "java21",
            "kotlin-current-target21",
            "standard-desugaring",
            "generated-multidex",
            "missing-dependency",
            "malformed-classfile",
            "unsupported-classfile",
            "duplicate-definition",
        )
        val EXPECTED_CASES = listOf(
            MatrixCase("java8", "JAVA_CLASSFILE", "8", "8", (24..36).toList(), listOf("DEBUG", "RELEASE"), COMPILE_SUCCESS),
            MatrixCase("java11", "JAVA_CLASSFILE", "11", "11", listOf(24, 36), listOf("DEBUG", "RELEASE"), COMPILE_SUCCESS),
            MatrixCase("java17", "JAVA_CLASSFILE", "17", "17", listOf(24, 36), listOf("DEBUG", "RELEASE"), COMPILE_SUCCESS),
            MatrixCase("java21", "JAVA_CLASSFILE", "21", "21", listOf(24, 36), listOf("DEBUG", "RELEASE"), COMPILE_SUCCESS),
            MatrixCase("kotlin-current-target21", "KOTLIN_CLASSFILE", "CURRENT", "21", listOf(24, 36), listOf("DEBUG", "RELEASE"), COMPILE_SUCCESS),
            MatrixCase("standard-desugaring", "STANDARD_DESUGARING", "17", "17", listOf(24, 26, 36), listOf("DEBUG", "RELEASE"), COMPILE_SUCCESS),
            MatrixCase("generated-multidex", "GENERATED_MULTIDEX", "21", "21", listOf(24, 36), listOf("DEBUG", "RELEASE"), COMPILE_SUCCESS),
            MatrixCase("missing-dependency", "MISSING_DEPENDENCY", "17", "17", listOf(24, 36), listOf("DEBUG"), COMPILE_SUCCESS),
            MatrixCase("malformed-classfile", "MALFORMED_CLASSFILE", "N/A", "N/A", listOf(24, 36), listOf("DEBUG"), COMPILE_FAILURE),
            MatrixCase("unsupported-classfile", "UNSUPPORTED_CLASSFILE", "UNSUPPORTED", "UNSUPPORTED", listOf(24, 36), listOf("DEBUG"), COMPILE_FAILURE),
            MatrixCase("duplicate-definition", "DUPLICATE_DEFINITION", "17", "17", listOf(24, 36), listOf("DEBUG"), COMPILE_FAILURE),
        ).associateBy { it.id }

        fun kotlinFixtureBytes(): ByteArray = requireNotNull(
            requireNotNull(D8UpgradeKotlinFixture::class.java.classLoader)
                .getResourceAsStream(KOTLIN_FIXTURE_RESOURCE),
        ) { "Compiled Kotlin fixture resource is missing: $KOTLIN_FIXTURE_RESOURCE" }.use { it.readBytes() }

        fun runtimeD8Version(): String {
            val versionString = Version.getVersionString()
            val coordinateVersion = versionString.substringBefore(' ')
            check(coordinateVersion.matches(Regex("^[0-9][0-9A-Za-z.+_-]{0,63}$"))) {
                "D8 returned an invalid runtime version string: $versionString"
            }
            return coordinateVersion
        }

        fun classFileMajorVersion(bytes: ByteArray): Int {
            require(bytes.size >= 8)
            require(bytes.copyOfRange(0, 4).contentEquals(byteArrayOf(0xca.toByte(), 0xfe.toByte(), 0xba.toByte(), 0xbe.toByte())))
            return ((bytes[6].toInt() and 0xff) shl 8) or (bytes[7].toInt() and 0xff)
        }

        fun classEntries(root: Path): Map<String, ByteArray> = Files.walk(root).use { stream ->
            stream.filter { Files.isRegularFile(it) && it.fileName.toString().endsWith(".class") }
                .sorted()
                .toList()
                .associate { path ->
                    root.relativize(path).toString().replace(File.separatorChar, '/') to Files.readAllBytes(path)
                }
        }

        fun writeStoredJar(path: Path, entries: Map<String, ByteArray>) {
            Files.createDirectories(path.parent)
            ZipOutputStream(Files.newOutputStream(path)).use { output ->
                entries.toSortedMap().forEach { (name, bytes) ->
                    val crc = CRC32().apply { update(bytes) }
                    val entry = ZipEntry(name).apply {
                        method = ZipEntry.STORED
                        size = bytes.size.toLong()
                        compressedSize = bytes.size.toLong()
                        this.crc = crc.value
                        time = 0L
                    }
                    output.putNextEntry(entry)
                    output.write(bytes)
                    output.closeEntry()
                }
            }
        }

        fun digestFixture(programFiles: List<Path>, classpathFiles: List<Path>): String {
            val digest = MessageDigest.getInstance("SHA-256")
            fun update(kind: String, path: Path) {
                digest.update(kind.toByteArray(StandardCharsets.UTF_8))
                digest.update(0)
                digest.update(path.fileName.toString().toByteArray(StandardCharsets.UTF_8))
                digest.update(0)
                if (Files.isRegularFile(path)) {
                    Files.newInputStream(path).use { input ->
                        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            digest.update(buffer, 0, count)
                        }
                    }
                } else {
                    digest.update("ABSENT".toByteArray(StandardCharsets.US_ASCII))
                }
                digest.update(0xff.toByte())
            }
            programFiles.forEach { update("PROGRAM", it) }
            classpathFiles.forEach { update("CLASSPATH", it) }
            return digest.digest().toHex()
        }

        fun digestNamedFiles(paths: List<Path>): String {
            val digest = MessageDigest.getInstance("SHA-256")
            paths.forEach { path ->
                digest.update(path.fileName.toString().toByteArray(StandardCharsets.US_ASCII))
                digest.update(0)
                Files.newInputStream(path).use { input ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        digest.update(buffer, 0, count)
                    }
                }
                digest.update(0xff.toByte())
            }
            return digest.digest().toHex()
        }

        fun sha256(path: Path): String {
            val digest = MessageDigest.getInstance("SHA-256")
            Files.newInputStream(path).use { input ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    digest.update(buffer, 0, count)
                }
            }
            return digest.digest().toHex()
        }

        fun ByteArray.toHex(): String = joinToString(separator = "") { byte -> "%02x".format(byte.toInt() and 0xff) }

        fun String.toCompilationMode(): CompilationMode = when (this) {
            "DEBUG" -> CompilationMode.DEBUG
            "RELEASE" -> CompilationMode.RELEASE
            else -> error("Unsupported D8 mode: $this")
        }

        fun String.boundedSummary(): String = replace(Regex("\\s+"), " ").trim().ifBlank { "Unavailable." }.take(1024)

        fun String.redactPrivatePaths(privateRoots: List<String>): String {
            var redacted = this
            privateRoots.forEach { privateRoot ->
                redacted = redacted.replace(privateRoot, "<private-path>", ignoreCase = true)
                redacted = redacted.replace(privateRoot.replace('\\', '/'), "<private-path>", ignoreCase = true)
            }
            redacted = WINDOWS_ABSOLUTE_PATH.replace(redacted, "<private-path>")
            redacted = UNIX_ABSOLUTE_PATH.replace(redacted, "<private-path>")
            return redacted
        }

        fun dexEntryOrdinal(name: String): Int = when (name) {
            "classes.dex" -> 1
            else -> name.removePrefix("classes").removeSuffix(".dex").toInt()
        }

        fun requiredSystemProperty(name: String): String =
            System.getProperty(name)?.takeIf { it.isNotBlank() }
                ?: throw AssertionError("Required JVM system property is missing: $name")

        val WINDOWS_ABSOLUTE_PATH = Regex("(?i)[A-Z]:[\\\\/][^|\\r\\n]+")
        val UNIX_ABSOLUTE_PATH = Regex("(?<![A-Za-z0-9._-])/(?:[^\\s|\\\"'<>]+)")
    }
}
