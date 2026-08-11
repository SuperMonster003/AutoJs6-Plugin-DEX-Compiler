package io.github.supermonster003.autojs6.plugin.dexcompiler.service

import java.util.concurrent.atomic.AtomicBoolean

/**
 * Owns the one-way transition to a remote session terminal state.
 *
 * Encoding and callback submission happen only after terminal ownership is claimed. If either
 * operation fails, work is stopped before the failure is rethrown. Cleanup remains a separate,
 * exactly-once operation because an in-flight D8 invocation must retain the process session gate
 * until its worker returns.
 */
internal class RemoteSessionTerminalController(
    private val stopWork: () -> Unit,
    private val cleanup: () -> Unit,
) {
    private val terminal = AtomicBoolean(false)
    private val stopAttempted = AtomicBoolean(false)
    private val cleaned = AtomicBoolean(false)

    val isTerminal: Boolean
        get() = terminal.get()

    fun <T> dispatchTerminal(
        stopWorkAfterDispatch: Boolean = false,
        encode: () -> T,
        dispatch: (T) -> Unit,
    ): Boolean {
        if (!terminal.compareAndSet(false, true)) return false
        try {
            dispatch(encode())
        } catch (error: Throwable) {
            stopAndRethrow(error)
        }
        if (stopWorkAfterDispatch) requestStop()
        return true
    }

    /** Claims terminal state if needed and always requests the at-most-once stop attempt. */
    fun abort(): Boolean {
        val claimed = terminal.compareAndSet(false, true)
        requestStop()
        return claimed
    }

    /** Stops an attempt with no worker-finally owner and releases its resources even if stop fails. */
    fun abortWithoutWorker() {
        finishWithoutWorker { abort() }
    }

    /** Runs setup before worker ownership; a thrown failure terminates and cleans the attempt. */
    fun <T> runBeforeWorker(action: () -> T): T {
        try {
            return action()
        } catch (error: Throwable) {
            failWithoutWorker(error)
        }
    }

    /** Runs a terminal path that has no worker-finally owner, then releases resources once. */
    fun finishWithoutWorker(action: () -> Unit) {
        var actionFailure: Throwable? = null
        try {
            action()
        } catch (error: Throwable) {
            actionFailure = error
        }
        var cleanupFailure: Throwable? = null
        try {
            cleanupOnce()
        } catch (error: Throwable) {
            cleanupFailure = error
        }
        val failure = when {
            actionFailure != null && cleanupFailure != null -> mergeFailures(actionFailure, cleanupFailure)
            actionFailure != null -> actionFailure
            else -> cleanupFailure
        }
        failure?.let { throw it }
    }

    fun cleanupOnce(): Boolean {
        if (!cleaned.compareAndSet(false, true)) return false
        cleanup()
        return true
    }

    private fun requestStop() {
        // Stop is attempted at most once. The session stop action must use finally for its
        // independent sub-actions; cleanup remains separately guarded and must never depend on
        // this attempt succeeding.
        if (stopAttempted.compareAndSet(false, true)) stopWork()
    }

    private fun failWithoutWorker(error: Throwable): Nothing {
        var stopFailure: Throwable? = null
        try {
            abort()
        } catch (failure: Throwable) {
            stopFailure = failure
        }
        var cleanupFailure: Throwable? = null
        try {
            cleanupOnce()
        } catch (failure: Throwable) {
            cleanupFailure = failure
        }
        var failure = error
        stopFailure?.let { failure = mergeFailures(failure, it) }
        cleanupFailure?.let { failure = mergeFailures(failure, it) }
        throw failure
    }

    private fun stopAndRethrow(error: Throwable): Nothing {
        try {
            requestStop()
        } catch (stopFailure: Throwable) {
            throw mergeFailures(error, stopFailure)
        }
        throw error
    }

    private fun mergeFailures(primary: Throwable, secondary: Throwable): Throwable {
        if (primary === secondary) return primary
        val preferred: Throwable
        val suppressed: Throwable
        when {
            primary is VirtualMachineError -> {
                preferred = primary
                suppressed = secondary
            }
            secondary is VirtualMachineError -> {
                preferred = secondary
                suppressed = primary
            }
            else -> {
                preferred = primary
                suppressed = secondary
            }
        }
        try {
            preferred.addSuppressed(suppressed)
        } catch (_: Throwable) {
            // Failure reporting must not replace the selected primary or skip resource cleanup.
        }
        return preferred
    }
}
