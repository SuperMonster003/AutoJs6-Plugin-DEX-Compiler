package io.github.supermonster003.autojs6.plugin.dexcompiler.service

import io.github.supermonster003.autojs6.plugin.dexcompiler.SingleActiveSessionGate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class RemoteSessionTerminalControllerTest {

    @Test
    fun encodeFailureStopsAndNoWorkerFinallyCleansExactlyOnce() {
        val fixture = Fixture()
        val failure = IllegalStateException("encode failed")

        val thrown = assertThrows(IllegalStateException::class.java) {
            fixture.controller.finishWithoutWorker {
                fixture.controller.dispatchTerminal<ByteArray>(
                    encode = { throw failure },
                    dispatch = { fixture.dispatchCount.incrementAndGet() },
                )
            }
        }

        assertSame(failure, thrown)
        assertTrue(fixture.controller.isTerminal)
        assertEquals(1, fixture.stopCount.get())
        assertEquals(0, fixture.dispatchCount.get())
        assertEquals(1, fixture.cleanupCount.get())
        assertFalse(fixture.controller.cleanupOnce())
    }

    @Test
    fun dispatchRejectionStopsAndNoWorkerFinallyCleansExactlyOnce() {
        val fixture = Fixture()
        val failure = RejectedExecutionException("callback lane rejected")

        val thrown = assertThrows(RejectedExecutionException::class.java) {
            fixture.controller.finishWithoutWorker {
                fixture.controller.dispatchTerminal(
                    encode = { byteArrayOf(1) },
                    dispatch = { throw failure },
                )
            }
        }

        assertSame(failure, thrown)
        assertEquals(1, fixture.stopCount.get())
        assertEquals(1, fixture.cleanupCount.get())
    }

    @Test
    fun virtualMachineErrorIsRethrownAfterFailClosedStopAndCleanup() {
        val fixture = Fixture()
        val failure = TestVirtualMachineError()

        val thrown = assertThrows(TestVirtualMachineError::class.java) {
            fixture.controller.finishWithoutWorker {
                fixture.controller.dispatchTerminal<ByteArray>(
                    encode = { throw failure },
                    dispatch = { fixture.dispatchCount.incrementAndGet() },
                )
            }
        }

        assertSame(failure, thrown)
        assertEquals(1, fixture.stopCount.get())
        assertEquals(1, fixture.cleanupCount.get())
    }

    @Test
    fun ordinaryStopFailureStillCleansAttemptWithoutWorkerExactlyOnce() {
        val failure = IllegalStateException("stop failed")
        val gate = SingleActiveSessionGate<Any>()
        val first = Any()
        val successor = Any()
        assertTrue(gate.tryAcquire(first))
        val fixture = Fixture(
            stopFailure = failure,
            afterCleanup = { assertTrue(gate.release(first)) },
        )

        val thrown = assertThrows(IllegalStateException::class.java) {
            fixture.controller.abortWithoutWorker()
        }

        assertSame(failure, thrown)
        assertTrue(fixture.controller.isTerminal)
        assertEquals(1, fixture.stopCount.get())
        assertEquals(1, fixture.cleanupCount.get())
        assertFalse(fixture.controller.cleanupOnce())
        assertFalse(fixture.controller.abort())
        assertEquals(1, fixture.stopCount.get())
        assertTrue(gate.tryAcquire(successor))
    }

    @Test
    fun stopVirtualMachineErrorStillCleansAttemptWithoutWorkerExactlyOnce() {
        val failure = TestVirtualMachineError()
        val fixture = Fixture(stopFailure = failure)

        val thrown = assertThrows(TestVirtualMachineError::class.java) {
            fixture.controller.abortWithoutWorker()
        }

        assertSame(failure, thrown)
        assertTrue(fixture.controller.isTerminal)
        assertEquals(1, fixture.stopCount.get())
        assertEquals(1, fixture.cleanupCount.get())
        assertFalse(fixture.controller.cleanupOnce())
    }

    @Test
    fun callbackVirtualMachineErrorRemainsPrimaryWhenFailureHandlerStopThrows() {
        val callbackFailure = TestVirtualMachineError()
        val stopFailure = IllegalStateException("stop failed")
        val fixture = Fixture(stopFailure = stopFailure)

        val thrown = assertThrows(TestVirtualMachineError::class.java) {
            rethrowCallbackVirtualMachineError(callbackFailure) {
                fixture.controller.abortWithoutWorker()
            }
        }

        assertSame(callbackFailure, thrown)
        assertEquals(listOf(stopFailure), thrown.suppressed.toList())
        assertEquals(1, fixture.stopCount.get())
        assertEquals(1, fixture.cleanupCount.get())
    }

    @Test
    fun callbackVirtualMachineErrorRemainsPrimaryWhenFailureHandlerStopThrowsVmError() {
        val callbackFailure = TestVirtualMachineError()
        val stopFailure = TestVirtualMachineError()
        val fixture = Fixture(stopFailure = stopFailure)

        val thrown = assertThrows(TestVirtualMachineError::class.java) {
            rethrowCallbackVirtualMachineError(callbackFailure) {
                fixture.controller.abortWithoutWorker()
            }
        }

        assertSame(callbackFailure, thrown)
        assertEquals(listOf(stopFailure), thrown.suppressed.toList())
        assertEquals(1, fixture.stopCount.get())
        assertEquals(1, fixture.cleanupCount.get())
    }

    @Test
    fun callbackLinkFailureBeforeWorkerReleasesGateAndPreservesVmErrorPriority() {
        val gate = SingleActiveSessionGate<Any>()
        val first = Any()
        val successor = Any()
        val linkFailure = TestVirtualMachineError()
        val stopFailure = IllegalStateException("stop failed")
        assertTrue(gate.tryAcquire(first))
        val fixture = Fixture(
            stopFailure = stopFailure,
            afterCleanup = { assertTrue(gate.release(first)) },
        )

        val thrown = assertThrows(TestVirtualMachineError::class.java) {
            fixture.controller.runBeforeWorker<Boolean> { throw linkFailure }
        }

        assertSame(linkFailure, thrown)
        assertEquals(listOf(stopFailure), thrown.suppressed.toList())
        assertTrue(fixture.controller.isTerminal)
        assertEquals(1, fixture.stopCount.get())
        assertEquals(1, fixture.cleanupCount.get())
        assertFalse(fixture.controller.cleanupOnce())
        assertTrue(gate.tryAcquire(successor))
    }

    @Test
    fun identicalLinkAndStopVmErrorStillCleansAndReleasesGate() {
        val gate = SingleActiveSessionGate<Any>()
        val first = Any()
        val successor = Any()
        val sharedFailure = TestVirtualMachineError()
        assertTrue(gate.tryAcquire(first))
        val fixture = Fixture(
            stopFailure = sharedFailure,
            afterCleanup = { assertTrue(gate.release(first)) },
        )

        val thrown = assertThrows(TestVirtualMachineError::class.java) {
            fixture.controller.runBeforeWorker<Boolean> { throw sharedFailure }
        }

        assertSame(sharedFailure, thrown)
        assertTrue(thrown.suppressed.isEmpty())
        assertEquals(1, fixture.stopCount.get())
        assertEquals(1, fixture.cleanupCount.get())
        assertFalse(fixture.controller.cleanupOnce())
        assertTrue(gate.tryAcquire(successor))
    }

    @Test
    fun cancellationStyleTerminalDuplicateAndCallbackFailureStopAtMostOnce() {
        val fixture = Fixture()

        assertTrue(
            fixture.controller.dispatchTerminal(
                stopWorkAfterDispatch = true,
                encode = { byteArrayOf(1) },
                dispatch = { fixture.dispatchCount.incrementAndGet() },
            ),
        )
        assertFalse(
            fixture.controller.dispatchTerminal(
                encode = { byteArrayOf(2) },
                dispatch = { fixture.dispatchCount.incrementAndGet() },
            ),
        )
        assertFalse(fixture.controller.abort())
        assertFalse(fixture.controller.abort())

        assertEquals(1, fixture.dispatchCount.get())
        assertEquals(1, fixture.stopCount.get())
    }

    @Test
    fun concurrentTerminalRaceHasOneEncoderAndDispatcher() {
        val fixture = Fixture()
        val encoderCount = AtomicInteger()
        val ready = CountDownLatch(CONTENDER_COUNT)
        val release = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(CONTENDER_COUNT)
        try {
            val results = (0 until CONTENDER_COUNT).map { contender ->
                executor.submit<Boolean> {
                    ready.countDown()
                    release.await()
                    fixture.controller.dispatchTerminal(
                        encode = {
                            encoderCount.incrementAndGet()
                            byteArrayOf(contender.toByte())
                        },
                        dispatch = { fixture.dispatchCount.incrementAndGet() },
                    )
                }
            }
            assertTrue(ready.await(5, TimeUnit.SECONDS))
            release.countDown()

            assertEquals(1, results.count { it.get(5, TimeUnit.SECONDS) })
            assertEquals(1, encoderCount.get())
            assertEquals(1, fixture.dispatchCount.get())
        } finally {
            executor.shutdownNow()
            assertTrue(executor.awaitTermination(5, TimeUnit.SECONDS))
        }
    }

    @Test
    fun cleanupReleasesGateForSuccessorExactlyOnce() {
        val gate = SingleActiveSessionGate<Any>()
        val first = Any()
        val successor = Any()
        val cleanupCount = AtomicInteger()
        assertTrue(gate.tryAcquire(first))
        val controller = RemoteSessionTerminalController(
            stopWork = {},
            cleanup = {
                cleanupCount.incrementAndGet()
                assertTrue(gate.release(first))
            },
        )

        assertTrue(controller.cleanupOnce())
        assertFalse(controller.cleanupOnce())

        assertEquals(1, cleanupCount.get())
        assertTrue(gate.tryAcquire(successor))
    }

    private class Fixture(
        private val stopFailure: Throwable? = null,
        private val afterCleanup: () -> Unit = {},
    ) {
        val stopCount = AtomicInteger()
        val cleanupCount = AtomicInteger()
        val dispatchCount = AtomicInteger()
        val controller = RemoteSessionTerminalController(
            stopWork = {
                stopCount.incrementAndGet()
                stopFailure?.let { throw it }
            },
            cleanup = {
                cleanupCount.incrementAndGet()
                afterCleanup()
            },
        )
    }

    private class TestVirtualMachineError : VirtualMachineError()

    private companion object {
        const val CONTENDER_COUNT = 8
    }
}
