package io.github.supermonster003.autojs6.plugin.dexcompiler

import java.util.concurrent.atomic.AtomicReference

/** Process-scoped, identity-based ownership for the single session advertised by protocol v1. */
internal class SingleActiveSessionGate<T : Any> {
    private val active = AtomicReference<T?>()

    fun tryAcquire(session: T): Boolean = active.compareAndSet(null, session)

    fun release(session: T): Boolean = active.compareAndSet(session, null)
}
