package io.github.supermonster003.autojs6.plugin.dexcompiler

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SingleActiveSessionGateTest {
    @Test
    fun gateUsesIdentityAndAllowsOnlyOneOwner() {
        val gate = SingleActiveSessionGate<Any>()
        val first = Any()
        val second = Any()

        assertTrue(gate.tryAcquire(first))
        assertFalse(gate.tryAcquire(second))
        assertFalse(gate.release(second))
        assertTrue(gate.release(first))
        assertTrue(gate.tryAcquire(second))
    }
}
