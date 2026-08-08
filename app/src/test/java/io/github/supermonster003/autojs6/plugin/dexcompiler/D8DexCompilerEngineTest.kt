package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files
import java.util.zip.ZipFile
import javax.tools.ToolProvider

class D8DexCompilerEngineTest {
    @Test
    fun realD8ProducesDexIndexedZip() {
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
            val d8Output = root.resolve("d8-output").apply { mkdir() }
            val artifact = D8DexCompilerEngine(runtime).compile(
                request = request,
                programJar = program,
                outputDirectory = d8Output,
                artifactZip = root.resolve("artifact.zip"),
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
        } finally {
            root.deleteRecursively()
        }
    }
}
