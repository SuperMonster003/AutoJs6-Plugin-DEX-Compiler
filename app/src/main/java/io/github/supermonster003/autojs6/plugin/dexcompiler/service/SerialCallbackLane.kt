package io.github.supermonster003.autojs6.plugin.dexcompiler.service

import android.util.Log
import java.io.Closeable
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ExecutorService
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

internal class SerialCallbackLane : Closeable {
    private val executor: ExecutorService = ThreadPoolExecutor(
        1,
        1,
        0L,
        TimeUnit.MILLISECONDS,
        ArrayBlockingQueue(MAX_PENDING_CALLBACKS),
        { runnable -> Thread(runnable, "dex-compiler-callback").apply { isDaemon = true } },
        ThreadPoolExecutor.AbortPolicy(),
    )

    fun dispatch(label: String, callback: () -> Unit, onFailure: (Throwable) -> Unit) {
        try {
            executor.execute {
                runCatching(callback).onFailure { error ->
                    Log.w(TAG, "DEX compiler callback failed: $label", error)
                    onFailure(error)
                }
            }
        } catch (error: RejectedExecutionException) {
            onFailure(error)
        }
    }

    override fun close() {
        executor.shutdownNow()
    }

    private companion object {
        const val TAG = "DexCompilerCallbackLane"
        const val MAX_PENDING_CALLBACKS = 64
    }
}
