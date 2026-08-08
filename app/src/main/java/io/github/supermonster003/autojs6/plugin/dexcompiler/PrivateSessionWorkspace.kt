package io.github.supermonster003.autojs6.plugin.dexcompiler

import android.content.Context
import java.io.Closeable
import java.io.File
import java.io.IOException
import java.util.UUID

internal class PrivateSessionWorkspace private constructor(
    private val root: File,
) : Closeable {
    val programJar = File(root, "program.jar")
    val d8OutputDirectory = File(root, "d8-output")
    val artifactZip = File(root, "artifact.zip")

    init {
        if (!d8OutputDirectory.mkdir()) {
            close()
            throw IOException("Failed to create the private D8 output directory")
        }
    }

    override fun close() {
        root.deleteRecursively()
    }

    companion object {
        fun create(context: Context): PrivateSessionWorkspace = createUnder(
            File(context.cacheDir, "dex-compiler-sessions"),
        )

        internal fun createUnder(baseDirectory: File): PrivateSessionWorkspace {
            if (!baseDirectory.exists() && !baseDirectory.mkdirs()) {
                throw IOException("Failed to create the private compiler workspace root")
            }
            val canonicalBase = baseDirectory.canonicalFile
            repeat(MAX_CREATION_ATTEMPTS) {
                val candidate = File(canonicalBase, "session-${UUID.randomUUID()}")
                if (candidate.mkdir()) {
                    val canonicalCandidate = candidate.canonicalFile
                    val expectedPrefix = canonicalBase.path + File.separator
                    if (!canonicalCandidate.path.startsWith(expectedPrefix)) {
                        candidate.deleteRecursively()
                        throw IOException("Compiler workspace escaped its private root")
                    }
                    return PrivateSessionWorkspace(canonicalCandidate)
                }
            }
            throw IOException("Failed to allocate a private compiler workspace")
        }

        private const val MAX_CREATION_ATTEMPTS = 8
    }
}
