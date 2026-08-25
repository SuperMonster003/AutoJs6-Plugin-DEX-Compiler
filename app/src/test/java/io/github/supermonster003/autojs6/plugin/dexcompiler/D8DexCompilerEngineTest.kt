package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files
import java.util.zip.ZipFile
import javax.tools.ToolProvider

class D8DexCompilerEngineTest {
    @Test
    fun realD8ProducesDexIndexedZipOnCommandAndCliCompatiblePaths() {
        val root = Files.createTempDirectory("d8-engine-test").toFile()
        try {
            val source = root.resolve("Hello.java").apply {
                writeText("public final class Hello { public static int answer() { return 42; } }")
            }
            val classes = root.resolve("classes").apply { mkdir() }
            val compiler = requireNotNull(ToolProvider.getSystemJavaCompiler())
            assertEquals(
                0,
                compiler.run(null, null, null, "-source", "8", "-target", "8", "-d", classes.path, source.path),
            )
            val program = root.resolve("program.jar")
            TestData.writeStoredJar(program, "Hello.class", classes.resolve("Hello.class").readBytes())

            val runtimeJar = root.resolve("runtime.jar")
            val objectClass = requireNotNull(Any::class.java.getResourceAsStream("/java/lang/Object.class")).use {
                it.readBytes()
            }
            TestData.writeStoredJar(runtimeJar, "java/lang/Object.class", objectClass)
            val runtime = RuntimeLibrarySet.fromFiles(listOf(runtimeJar))
            val request = TestData.request(program.readBytes(), runtime)
            listOf(25, 26).forEach { sdk ->
                val d8Output = root.resolve("d8-output-$sdk").apply { mkdir() }
                val artifact = D8DexCompilerEngine(runtime, sdkInt = { sdk }).compile(
                    request = request,
                    programJar = program,
                    outputDirectory = d8Output,
                    artifactZip = root.resolve("artifact-$sdk.zip"),
                    ensureActive = {},
                    beforePackaging = {},
                )

                ZipFile(artifact.file).use { zip ->
                    val entry = requireNotNull(zip.getEntry("classes.dex"))
                    val magic = zip.getInputStream(entry).use { it.readNBytes(8) }
                    assertTrue(magic.copyOfRange(0, 4).contentEquals("dex\n".toByteArray(Charsets.US_ASCII)))
                }
                assertEquals(1, artifact.dexEntryCount)
                assertEquals(artifact.file.length(), artifact.outputSizeBytes)
            }
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun realD8KeepsClasspathOutOfProgramOutput() {
        val root = Files.createTempDirectory("d8-real-classpath-test").toFile()
        try {
            val compiler = requireNotNull(ToolProvider.getSystemJavaCompiler())
            val dependencySource = root.resolve("ClasspathOnlyDep.java").apply {
                writeText(
                    """
                    package fixture.classpath;
                    public final class ClasspathOnlyDep {
                        public static int value() { return 41; }
                    }
                    """.trimIndent(),
                )
            }
            val dependencyClasses = root.resolve("dependency-classes").apply { mkdir() }
            assertEquals(
                0,
                compiler.run(
                    null,
                    null,
                    null,
                    "-source", "8",
                    "-target", "8",
                    "-d", dependencyClasses.path,
                    dependencySource.path,
                ),
            )

            val programSource = root.resolve("ProgramUsesClasspath.java").apply {
                writeText(
                    """
                    package fixture.classpath;
                    public final class ProgramUsesClasspath {
                        public static int answer() { return ClasspathOnlyDep.value() + 1; }
                    }
                    """.trimIndent(),
                )
            }
            val programClasses = root.resolve("program-classes").apply { mkdir() }
            assertEquals(
                0,
                compiler.run(
                    null,
                    null,
                    null,
                    "-source", "8",
                    "-target", "8",
                    "-classpath", dependencyClasses.path,
                    "-d", programClasses.path,
                    programSource.path,
                ),
            )

            val dependencyJar = root.resolve("dependency.jar")
            TestData.writeStoredJar(
                dependencyJar,
                DEPENDENCY_CLASS_ENTRY,
                dependencyClasses.resolve(DEPENDENCY_CLASS_ENTRY).readBytes(),
            )
            val programJar = root.resolve("program.jar")
            TestData.writeStoredJar(
                programJar,
                PROGRAM_CLASS_ENTRY,
                programClasses.resolve(PROGRAM_CLASS_ENTRY).readBytes(),
            )
            val runtimeJar = root.resolve("runtime.jar")
            val objectClass = requireNotNull(Any::class.java.getResourceAsStream("/java/lang/Object.class")).use {
                it.readBytes()
            }
            TestData.writeStoredJar(runtimeJar, "java/lang/Object.class", objectClass)
            val runtime = RuntimeLibrarySet.fromFiles(listOf(runtimeJar))
            val request = TestData.request(programJar.readBytes(), runtime)
            val engine = D8DexCompilerEngine(runtimeLibraries = runtime, sdkInt = { 26 })

            val withClasspath = engine.compile(
                request = request,
                programJar = programJar,
                classpathJars = listOf(dependencyJar),
                outputDirectory = root.resolve("with-classpath-output").apply { mkdir() },
                artifactZip = root.resolve("with-classpath.zip"),
                ensureActive = {},
                beforePackaging = {},
            ).singleDexBytes()
            assertEquals(setOf(PROGRAM_DESCRIPTOR), withClasspath.definedClassDescriptors())
            assertTrue(
                "The program DEX must retain its external dependency reference",
                withClasspath.toString(Charsets.ISO_8859_1).contains(DEPENDENCY_DESCRIPTOR),
            )

        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun api26CommandRunnerReceivesOrderedClasspathAndSeparateRuntimeLibraries() {
        val root = Files.createTempDirectory("d8-command-classpath-test").toFile()
        try {
            val program = root.resolve("program.jar").apply { writeBytes(byteArrayOf(1)) }
            val firstClasspath = root.resolve("classpath-first.jar").apply { writeBytes(byteArrayOf(2)) }
            val secondClasspath = root.resolve("classpath-second.jar").apply { writeBytes(byteArrayOf(3)) }
            val firstRuntime = root.resolve("runtime-first.jar").apply { writeBytes(byteArrayOf(4)) }
            val secondRuntime = root.resolve("runtime-second.jar").apply { writeBytes(byteArrayOf(5)) }
            val runtime = RuntimeLibrarySet.fromFiles(listOf(firstRuntime, secondRuntime))
            val request = TestData.request(program.readBytes(), runtime)
            val output = root.resolve("d8-output").apply { mkdir() }
            var commandInvoked = false

            val artifact = D8DexCompilerEngine(
                runtimeLibraries = runtime,
                sdkInt = { 26 },
                commandRunner = D8CommandRunner { actualRequest, inputs, outputDirectory, libraries, _ ->
                    commandInvoked = true
                    assertSame(request, actualRequest)
                    assertEquals(program, inputs.programJar)
                    assertEquals(listOf(firstClasspath, secondClasspath), inputs.classpathJars)
                    assertEquals(runtime.files, libraries)
                    outputDirectory.resolve("classes.dex").writeBytes(byteArrayOf(0x64, 0x65, 0x78))
                },
                cliRunner = D8CliRunner { _, _ -> throw AssertionError("API 26 must not use the CLI runner") },
            ).compile(
                request = request,
                programJar = program,
                classpathJars = listOf(firstClasspath, secondClasspath),
                outputDirectory = output,
                artifactZip = root.resolve("artifact.zip"),
                ensureActive = {},
                beforePackaging = {},
            )

            assertTrue(commandInvoked)
            assertEquals(1, artifact.dexEntryCount)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun api25CliArgumentsKeepLibrariesAndOrderedClasspathBeforeProgram() {
        val root = Files.createTempDirectory("d8-cli-classpath-test").toFile()
        try {
            val program = root.resolve("program.jar").apply { writeBytes(byteArrayOf(1)) }
            val firstClasspath = root.resolve("classpath-first.jar").apply { writeBytes(byteArrayOf(2)) }
            val secondClasspath = root.resolve("classpath-second.jar").apply { writeBytes(byteArrayOf(3)) }
            val firstRuntime = root.resolve("runtime-first.jar").apply { writeBytes(byteArrayOf(4)) }
            val secondRuntime = root.resolve("runtime-second.jar").apply { writeBytes(byteArrayOf(5)) }
            val runtime = RuntimeLibrarySet.fromFiles(listOf(firstRuntime, secondRuntime))
            val request = TestData.request(program.readBytes(), runtime)
            val output = root.resolve("d8-output").apply { mkdir() }
            var capturedArguments: List<String>? = null

            D8DexCompilerEngine(
                runtimeLibraries = runtime,
                sdkInt = { 25 },
                commandRunner = D8CommandRunner { _, _, _, _, _ ->
                    throw AssertionError("API 25 must not use the command runner")
                },
                cliRunner = D8CliRunner { arguments, _ ->
                    capturedArguments = arguments.toList()
                    output.resolve("classes.dex").writeBytes(byteArrayOf(0x64, 0x65, 0x78))
                },
            ).compile(
                request = request,
                programJar = program,
                classpathJars = listOf(firstClasspath, secondClasspath),
                outputDirectory = output,
                artifactZip = root.resolve("artifact.zip"),
                ensureActive = {},
                beforePackaging = {},
            )

            assertEquals(
                listOf(
                    "--output", output.absolutePath,
                    "--release",
                    "--min-api", "24",
                    "--lib", runtime.files[0].absolutePath,
                    "--lib", runtime.files[1].absolutePath,
                    "--classpath", firstClasspath.absolutePath,
                    "--classpath", secondClasspath.absolutePath,
                    program.absolutePath,
                ),
                capturedArguments,
            )
        } finally {
            root.deleteRecursively()
        }
    }

    private fun DexArtifact.singleDexBytes(): ByteArray = ZipFile(file).use { zip ->
        val entries = zip.entries().asSequence().toList()
        assertEquals(listOf("classes.dex"), entries.map { it.name })
        zip.getInputStream(entries.single()).use { it.readBytes() }
    }

    /** Reads only the DEX tables needed to distinguish definitions from referenced type IDs. */
    private fun ByteArray.definedClassDescriptors(): Set<String> {
        require(size >= DEX_HEADER_SIZE)
        require(copyOfRange(0, 4).contentEquals("dex\n".toByteArray(Charsets.US_ASCII)))
        require(u32(DEX_HEADER_SIZE_OFFSET) == DEX_HEADER_SIZE)
        require(u32(DEX_ENDIAN_TAG_OFFSET) == DEX_ENDIAN_CONSTANT)

        val stringIdsSize = u32(DEX_STRING_IDS_SIZE_OFFSET)
        val stringIdsOffset = u32(DEX_STRING_IDS_OFFSET_OFFSET)
        val typeIdsSize = u32(DEX_TYPE_IDS_SIZE_OFFSET)
        val typeIdsOffset = u32(DEX_TYPE_IDS_OFFSET_OFFSET)
        val classDefsSize = u32(DEX_CLASS_DEFS_SIZE_OFFSET)
        val classDefsOffset = u32(DEX_CLASS_DEFS_OFFSET_OFFSET)
        require(classDefsSize <= typeIdsSize)

        return buildSet(classDefsSize) {
            repeat(classDefsSize) { index ->
                val classDefOffset = checkedTableOffset(classDefsOffset, index, DEX_CLASS_DEF_ITEM_SIZE)
                val classIndex = u32(classDefOffset)
                require(classIndex < typeIdsSize)
                val typeIdOffset = checkedTableOffset(typeIdsOffset, classIndex, DEX_TYPE_ID_ITEM_SIZE)
                val descriptorIndex = u32(typeIdOffset)
                require(descriptorIndex < stringIdsSize)
                val stringIdOffset = checkedTableOffset(stringIdsOffset, descriptorIndex, DEX_STRING_ID_ITEM_SIZE)
                add(readAsciiDexString(u32(stringIdOffset)))
            }
        }
    }

    private fun ByteArray.checkedTableOffset(base: Int, index: Int, itemSize: Int): Int {
        val offset = base.toLong() + index.toLong() * itemSize.toLong()
        require(offset >= 0L && offset + itemSize <= size.toLong())
        return offset.toInt()
    }

    private fun ByteArray.u32(offset: Int): Int {
        require(offset >= 0 && offset.toLong() + Int.SIZE_BYTES <= size.toLong())
        val value = (this[offset].toLong() and 0xffL) or
            ((this[offset + 1].toLong() and 0xffL) shl 8) or
            ((this[offset + 2].toLong() and 0xffL) shl 16) or
            ((this[offset + 3].toLong() and 0xffL) shl 24)
        require(value <= Int.MAX_VALUE)
        return value.toInt()
    }

    private fun ByteArray.readAsciiDexString(offset: Int): String {
        require(offset in indices)
        var cursor = offset
        var byteCount = 0
        while (byteCount < 5) {
            require(cursor in indices)
            val value = this[cursor++].toInt() and 0xff
            byteCount += 1
            if (value and 0x80 == 0) break
            require(byteCount < 5)
        }
        val start = cursor
        while (true) {
            require(cursor in indices)
            val value = this[cursor].toInt() and 0xff
            if (value == 0) break
            require(value in 0x01..0x7f) { "Expected an ASCII class descriptor" }
            cursor += 1
        }
        return String(this, start, cursor - start, Charsets.US_ASCII)
    }

    private companion object {
        const val DEPENDENCY_CLASS_ENTRY = "fixture/classpath/ClasspathOnlyDep.class"
        const val PROGRAM_CLASS_ENTRY = "fixture/classpath/ProgramUsesClasspath.class"
        const val DEPENDENCY_DESCRIPTOR = "Lfixture/classpath/ClasspathOnlyDep;"
        const val PROGRAM_DESCRIPTOR = "Lfixture/classpath/ProgramUsesClasspath;"

        const val DEX_HEADER_SIZE = 112
        const val DEX_HEADER_SIZE_OFFSET = 36
        const val DEX_ENDIAN_TAG_OFFSET = 40
        const val DEX_ENDIAN_CONSTANT = 0x12345678
        const val DEX_STRING_IDS_SIZE_OFFSET = 56
        const val DEX_STRING_IDS_OFFSET_OFFSET = 60
        const val DEX_TYPE_IDS_SIZE_OFFSET = 64
        const val DEX_TYPE_IDS_OFFSET_OFFSET = 68
        const val DEX_CLASS_DEFS_SIZE_OFFSET = 96
        const val DEX_CLASS_DEFS_OFFSET_OFFSET = 100
        const val DEX_STRING_ID_ITEM_SIZE = 4
        const val DEX_TYPE_ID_ITEM_SIZE = 4
        const val DEX_CLASS_DEF_ITEM_SIZE = 32
    }
}
