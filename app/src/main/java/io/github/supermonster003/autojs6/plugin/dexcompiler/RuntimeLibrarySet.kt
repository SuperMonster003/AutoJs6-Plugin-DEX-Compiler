package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.autojs.plugin.dexcompiler.api.DexCompilerContract
import org.autojs.plugin.dexcompiler.api.DexRuntimeLibraryFingerprint
import org.autojs.plugin.dexcompiler.api.DexRuntimeLibraryIdentity
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

internal class RuntimeLibrarySet private constructor(
    val files: List<File>,
    val identities: List<DexRuntimeLibraryIdentity>,
) {
    val fingerprint = DexRuntimeLibraryFingerprint.compute(identities)

    companion object {
        fun discover(): RuntimeLibrarySet {
            val pathGroups = listOfNotNull(
                System.getProperty("java.boot.class.path"),
                System.getenv("BOOTCLASSPATH"),
                System.getenv("DEX2OATBOOTCLASSPATH"),
            )
            return fromPathGroups(pathGroups)
        }

        internal fun fromPathGroups(pathGroups: Collection<String>): RuntimeLibrarySet {
            val seen = HashSet<String>()
            val files = pathGroups.asSequence()
                .flatMap { it.split(File.pathSeparatorChar).asSequence() }
                .map(String::trim)
                .filter(String::isNotEmpty)
                .map(::File)
                .mapNotNull { runCatching { it.canonicalFile }.getOrNull() }
                .filter { it.isFile && it.canRead() }
                .filter { seen.add(it.path) }
                .toList()
            return fromFiles(files)
        }

        internal fun fromFiles(files: Collection<File>): RuntimeLibrarySet {
            require(files.isNotEmpty()) { "No readable device runtime boot-classpath files were found" }
            require(files.size <= DexCompilerContract.MAX_RUNTIME_LIBRARY_IDENTITIES) {
                "Device runtime boot classpath has too many entries"
            }
            val canonicalFiles = files.map { file ->
                file.canonicalFile.also {
                    require(it.isFile && it.canRead()) { "Runtime library is not a readable file: $it" }
                }
            }
            require(canonicalFiles.map(File::getPath).toSet().size == canonicalFiles.size) {
                "Device runtime boot classpath contains duplicate files"
            }
            val identities = canonicalFiles.map(::readIdentity)
            return RuntimeLibrarySet(canonicalFiles, identities)
        }

        private fun readIdentity(file: File): DexRuntimeLibraryIdentity {
            val digest = MessageDigest.getInstance("SHA-256")
            var size = 0L
            FileInputStream(file).buffered().use { input ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    if (read == 0) continue
                    size = Math.addExact(size, read.toLong())
                    digest.update(buffer, 0, read)
                }
            }
            return DexRuntimeLibraryIdentity(
                sizeBytes = size,
                contentSha256 = org.autojs.plugin.dexcompiler.api.DexSha256.fromBytes(digest.digest()),
            )
        }
    }
}
