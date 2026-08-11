package io.github.supermonster003.autojs6.plugin.dexcompiler

import android.content.Context
import org.autojs.plugin.dexcompiler.api.DexCompilerContract
import java.io.Closeable
import java.io.File
import java.io.IOException
import java.util.UUID

internal class PrivateSessionWorkspace private constructor(
    private val root: File,
) : Closeable {
    val programJar = File(root, "program.jar")
    private val classpathDirectory = File(root, "classpath")
    val d8OutputDirectory = File(root, "d8-output")
    val artifactZip = File(root, "artifact.zip")

    init {
        if (!classpathDirectory.mkdir() || !d8OutputDirectory.mkdir()) {
            close()
            throw IOException("Failed to create the private compiler workspace directories")
        }
    }

    fun classpathJar(ordinal: Int): File {
        require(ordinal in 0 until DexCompilerContract.MAX_CLASSPATH_JARS) {
            "Classpath ordinal is outside the protocol limit"
        }
        return File(classpathDirectory, "classpath-${ordinal.toString().padStart(2, '0')}.jar")
    }

    override fun close() {
        root.deleteRecursively()
    }

    companion object {
        fun create(context: Context): PrivateSessionWorkspace = createUnder(
            File(context.cacheDir, "dex-compiler-sessions"),
        )

        /**
         * Removes workspaces left by a previous provider process that could not run [close].
         *
         * The caller must invoke this only once at process startup, before exposing the Binder.
         * Running it for every Service instance could delete a still-live worker's workspace when
         * Android recreates the Service without replacing the process.
         */
        fun recoverStale(context: Context) {
            val canonicalCache = try {
                context.cacheDir.canonicalFile
            } catch (error: IOException) {
                throw IOException("Unable to resolve the private cache directory", error)
            }
            recoverStaleUnder(File(canonicalCache, "dex-compiler-sessions"))
        }

        internal fun recoverStaleUnder(baseDirectory: File) {
            val absoluteBase = baseDirectory.absoluteFile
            val canonicalBase = try {
                baseDirectory.canonicalFile
            } catch (error: IOException) {
                throw IOException("Unable to resolve the private compiler workspace root", error)
            }
            if (canonicalBase.path != absoluteBase.path) {
                throw IOException("Private compiler workspace root is not canonical")
            }
            if (!canonicalBase.exists()) return
            if (!canonicalBase.isDirectory) {
                throw IOException("Private compiler workspace root is not a directory")
            }
            val children = canonicalBase.listFiles()
                ?: throw IOException("Unable to enumerate stale compiler workspaces")
            children
                .filter { SESSION_DIRECTORY.matches(it.name) }
                .forEach { candidate ->
                    val canonicalCandidate = try {
                        candidate.canonicalFile
                    } catch (error: IOException) {
                        throw IOException("Unable to resolve a stale compiler workspace", error)
                    }
                    val expectedPath = canonicalBase.path + File.separator + candidate.name
                    if (!candidate.isDirectory || canonicalCandidate.path != expectedPath) {
                        throw IOException("Stale compiler workspace is not a canonical direct directory")
                    }
                    deleteCanonicalTree(candidate, canonicalBase)
                }
        }

        private fun deleteCanonicalTree(node: File, canonicalBase: File) {
            val absoluteNode = node.absoluteFile
            val canonicalNode = try {
                node.canonicalFile
            } catch (error: IOException) {
                throw IOException("Unable to resolve a stale compiler workspace entry", error)
            }
            val allowedPrefix = canonicalBase.path + File.separator
            if (canonicalNode.path != absoluteNode.path || !canonicalNode.path.startsWith(allowedPrefix)) {
                throw IOException("Stale compiler workspace entry is not a canonical child")
            }
            when {
                node.isDirectory -> {
                    val children = node.listFiles()
                        ?: throw IOException("Unable to enumerate a stale compiler workspace")
                    children.forEach { child -> deleteCanonicalTree(child, canonicalBase) }
                }
                node.isFile -> Unit
                else -> throw IOException("Stale compiler workspace entry has an unsupported file type")
            }
            if (!node.delete() || node.exists()) {
                throw IOException("Unable to remove a stale compiler workspace entry")
            }
        }

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
        private val SESSION_DIRECTORY = Regex(
            "^session-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
        )
    }
}

/** Runs a successful startup recovery at most once for the lifetime of this process. */
internal class ProcessWorkspaceRecovery {
    @Volatile
    private var completed = false

    fun ensureRecovered(recover: () -> Unit) {
        if (completed) return
        synchronized(this) {
            if (completed) return
            recover()
            completed = true
        }
    }
}
