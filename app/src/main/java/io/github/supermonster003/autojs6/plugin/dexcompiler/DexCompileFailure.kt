package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.autojs.plugin.dexcompiler.api.DexCompilerErrorCode
import org.autojs.plugin.dexcompiler.api.DexCompilerFailurePhase

internal class DexCompileFailure(
    val code: DexCompilerErrorCode,
    val phase: DexCompilerFailurePhase,
    message: String,
    cause: Throwable? = null,
) : IllegalArgumentException(message, cause)
