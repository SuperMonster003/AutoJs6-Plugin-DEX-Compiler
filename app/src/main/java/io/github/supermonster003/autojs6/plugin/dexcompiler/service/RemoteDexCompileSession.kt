package io.github.supermonster003.autojs6.plugin.dexcompiler.service

import android.content.Context
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.RemoteException
import android.os.SystemClock
import io.github.supermonster003.autojs6.plugin.dexcompiler.D8DexCompilerEngine
import io.github.supermonster003.autojs6.plugin.dexcompiler.DexArtifact
import io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompileFailure
import io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerInputMaterializer
import io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerRuntime
import io.github.supermonster003.autojs6.plugin.dexcompiler.PrivateSessionWorkspace
import io.github.supermonster003.autojs6.plugin.dexcompiler.RuntimeLibrarySet
import org.autojs.plugin.dexcompiler.api.DexCompileCancellation
import org.autojs.plugin.dexcompiler.api.DexCompileError
import org.autojs.plugin.dexcompiler.api.DexCompileProgress
import org.autojs.plugin.dexcompiler.api.DexCompileRequest
import org.autojs.plugin.dexcompiler.api.DexCompileResult
import org.autojs.plugin.dexcompiler.api.DexCompileStarted
import org.autojs.plugin.dexcompiler.api.DexCompilerCancellationReason
import org.autojs.plugin.dexcompiler.api.DexCompilerCapabilities
import org.autojs.plugin.dexcompiler.api.DexCompilerCodec
import org.autojs.plugin.dexcompiler.api.DexCompilerContractException
import org.autojs.plugin.dexcompiler.api.DexCompilerContractViolation
import org.autojs.plugin.dexcompiler.api.DexCompilerErrorCode
import org.autojs.plugin.dexcompiler.api.DexCompilerDiagnostic
import org.autojs.plugin.dexcompiler.api.DexCompilerFailurePhase
import org.autojs.plugin.dexcompiler.api.DexCompilerFamily
import org.autojs.plugin.dexcompiler.api.DexCompilerProgressStage
import org.autojs.plugin.dexcompiler.api.DexCompilerValidation
import org.autojs.plugin.dexcompiler.api.DexRequestId
import org.autojs.plugin.dexcompiler.api.IDexCompilerCallback
import org.autojs.plugin.dexcompiler.api.IDexCompilerSession
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

internal class RemoteDexCompileSession(
    private val context: Context,
    private val ownerUid: Int,
    requestMetadata: ByteArray,
    private val descriptors: OwnedParcelFileDescriptors,
    private val callback: IDexCompilerCallback,
    private val capabilities: DexCompilerCapabilities,
    runtimeLibraries: RuntimeLibrarySet,
    private val callerVerifier: HostCallerVerifier,
    private val worker: ExecutorService,
    private val callbackLane: SerialCallbackLane,
    private val onFinished: (RemoteDexCompileSession) -> Unit,
) : IDexCompilerSession.Stub() {
    private val decodedRequest: Result<DexCompileRequest> = try {
        Result.success(DexCompilerCodec.decodeRequest(requestMetadata))
    } catch (error: VirtualMachineError) {
        throw error
    } catch (error: Throwable) {
        Result.failure(error)
    }
    private val requestIdHint = decodedRequest.getOrNull()?.requestId ?: ZERO_REQUEST_ID
    private val engine = D8DexCompilerEngine(runtimeLibraries)
    private val outputClaimed = AtomicBoolean(false)
    private val callbackDeathLinked = AtomicBoolean(false)
    private val workScheduled = AtomicBoolean(false)
    private val workerThread = AtomicReference<Thread?>()
    private val terminalController = RemoteSessionTerminalController(
        stopWork = ::stopWork,
        cleanup = ::cleanupResources,
    )
    private val sequence = AtomicLong(0L)
    private val createdAtMillis = SystemClock.elapsedRealtime()
    private val callbackBinder = callback.asBinder()
    private val callbackDeathRecipient = IBinder.DeathRecipient(::callbackDied)

    @Volatile
    private var workspace: PrivateSessionWorkspace? = null

    override fun cancel() {
        callerVerifier.enforceSessionOwner(ownerUid)
        finishCancellation(DexCompilerCancellationReason.REQUESTED)
    }

    override fun close() {
        callerVerifier.enforceSessionOwner(ownerUid)
        finishCancellation(DexCompilerCancellationReason.SESSION_CLOSED)
    }

    fun start() {
        if (!terminalController.runBeforeWorker(::linkCallbackDeath)) {
            cleanup()
            return
        }
        submitWorker()
    }

    fun rejectBusy() {
        if (!terminalController.runBeforeWorker(::linkCallbackDeath)) {
            cleanup()
            return
        }
        terminalController.finishWithoutWorker {
            finishError(
                requestId = requestIdHint,
                code = DexCompilerErrorCode.BUSY,
                phase = DexCompilerFailurePhase.QUEUE,
                message = "DEX compiler already has an active session",
            )
        }
    }

    fun serviceDestroyed() {
        abortAndCleanupIfNoWorker()
    }

    private fun submitWorker() {
        workScheduled.set(true)
        try {
            worker.execute {
                workerThread.set(Thread.currentThread())
                try {
                    runCompilation()
                } finally {
                    workerThread.compareAndSet(Thread.currentThread(), null)
                    cleanup()
                }
            }
        } catch (error: RejectedExecutionException) {
            workScheduled.set(false)
            terminalController.finishWithoutWorker {
                finishError(
                    requestIdHint,
                    DexCompilerErrorCode.INTERNAL,
                    DexCompilerFailurePhase.QUEUE,
                    "DEX compiler worker is unavailable",
                )
            }
        } catch (error: Throwable) {
            workScheduled.set(false)
            try {
                terminalController.abort()
            } finally {
                cleanup()
            }
            throw error
        }
    }

    private fun runCompilation() {
        val request = try {
            decodedRequest.getOrThrow().also { value ->
                if (!DexCompilerRuntime.supportsProtocolVersion(value.protocolVersion)) {
                    throw DexCompilerContractException(
                        DexCompilerContractViolation.PROTOCOL_INCOMPATIBLE,
                        "Compile request protocol version is not supported by this provider",
                    )
                }
                DexCompilerValidation.validateRequestAgainst(
                    value,
                    capabilities,
                    value.protocolVersion,
                )
            }
        } catch (error: DexCompilerContractException) {
            finishContractError(error)
            return
        } catch (error: VirtualMachineError) {
            throw error
        } catch (error: Throwable) {
            finishError(
                requestIdHint,
                DexCompilerErrorCode.INVALID_REQUEST,
                DexCompilerFailurePhase.INPUT_VALIDATION,
                error.message ?: "Compile request metadata is malformed",
            )
            return
        }

        try {
            ensureActive()
            emitStarted(request)
            ensureActive()
            emitProgress(request, DexCompilerProgressStage.VALIDATING)
            ensureActive()

            val privateWorkspace = PrivateSessionWorkspace.create(context).also { workspace = it }
            val input = ParcelFileDescriptor.AutoCloseInputStream(descriptors.program)
            val materializedInputs = try {
                val inputs = DexCompilerInputMaterializer.materialize(
                    request = request,
                    input = input,
                    workspace = privateWorkspace,
                    capabilities = capabilities,
                    ensureActive = ::ensureActive,
                )
                descriptors.program.checkError()
                inputs
            } finally {
                input.close()
            }

            ensureActive()
            emitProgress(request, DexCompilerProgressStage.COMPILING)
            ensureActive()
            val artifact = engine.compile(
                request = request,
                programJar = materializedInputs.programJar,
                classpathJars = materializedInputs.classpathJars,
                outputDirectory = privateWorkspace.d8OutputDirectory,
                artifactZip = privateWorkspace.artifactZip,
                ensureActive = ::ensureActive,
                beforePackaging = { emitProgress(request, DexCompilerProgressStage.PACKAGING) },
            )

            ensureActive()
            emitProgress(request, DexCompilerProgressStage.WRITING)
            ensureActive()
            writeArtifact(artifact)
            ensureActive()
            finishCompleted(request, artifact)
        } catch (_: SessionStopped) {
            Unit
        } catch (error: DexCompileFailure) {
            finishError(
                request.requestId,
                error.code,
                error.phase,
                error.message ?: "DEX compilation failed",
                error.diagnostics,
            )
        } catch (error: IOException) {
            if (!terminalController.isTerminal) {
                finishError(
                    request.requestId,
                    DexCompilerErrorCode.STORAGE_EXHAUSTED,
                    DexCompilerFailurePhase.OUTPUT_WRITE,
                    error.message ?: "DEX compiler storage operation failed",
                )
            }
        } catch (error: VirtualMachineError) {
            throw error
        } catch (error: Throwable) {
            if (!terminalController.isTerminal) {
                finishError(
                    request.requestId,
                    DexCompilerErrorCode.INTERNAL,
                    DexCompilerFailurePhase.COMPILATION,
                    error.message ?: "Unexpected DEX compiler failure",
                )
            }
        }
    }

    private fun writeArtifact(artifact: DexArtifact) {
        check(outputClaimed.compareAndSet(false, true)) { "Output writer may only be used once" }
        var copied = 0L
        try {
            val output = ParcelFileDescriptor.AutoCloseOutputStream(descriptors.output)
            try {
                artifact.file.inputStream().buffered().use { input ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        ensureActive()
                        val read = input.read(buffer)
                        if (read < 0) break
                        if (read == 0) continue
                        output.write(buffer, 0, read)
                        copied = Math.addExact(copied, read.toLong())
                    }
                }
                output.flush()
                descriptors.output.checkError()
            } finally {
                output.close()
            }
        } catch (error: SessionStopped) {
            throw error
        } catch (error: IOException) {
            throw DexCompileFailure(
                DexCompilerErrorCode.STORAGE_EXHAUSTED,
                DexCompilerFailurePhase.OUTPUT_WRITE,
                "Failed to write the DEX ZIP",
                error,
            )
        }
        if (copied != artifact.outputSizeBytes) {
            throw DexCompileFailure(
                DexCompilerErrorCode.INTERNAL,
                DexCompilerFailurePhase.OUTPUT_WRITE,
                "DEX ZIP changed while it was being written",
            )
        }
    }

    private fun emitStarted(request: DexCompileRequest) {
        val payload = DexCompilerCodec.encodeStarted(
            DexCompileStarted(
                requestId = request.requestId,
                sequence = sequence.getAndIncrement(),
                protocolVersion = request.protocolVersion,
                compilerFamily = DexCompilerFamily.D8,
                compilerVersion = DexCompilerRuntime.COMPILER_VERSION,
                runtimeLibraryModel = request.runtimeLibraryModel,
                runtimeLibraryFingerprint = capabilities.runtimeLibraryFingerprint,
                queueElapsedMillis = elapsedMillis(),
            ),
        )
        dispatchCallback("started") { callback.onStarted(payload) }
    }

    private fun emitProgress(request: DexCompileRequest, stage: DexCompilerProgressStage) {
        val payload = DexCompilerCodec.encodeProgress(
            DexCompileProgress(
                requestId = request.requestId,
                sequence = sequence.getAndIncrement(),
                stage = stage,
            ),
        )
        dispatchCallback("progress") { callback.onProgress(payload) }
    }

    private fun finishCompleted(request: DexCompileRequest, artifact: DexArtifact) {
        terminalController.dispatchTerminal(
            encode = {
                DexCompilerCodec.encodeResult(
                    DexCompileResult(
                        requestId = request.requestId,
                        compilerFamily = DexCompilerFamily.D8,
                        compilerVersion = DexCompilerRuntime.COMPILER_VERSION,
                        mode = request.mode,
                        minApi = request.minApi,
                        outputFormat = request.outputFormat,
                        runtimeLibraryFingerprint = capabilities.runtimeLibraryFingerprint,
                        outputSizeBytes = artifact.outputSizeBytes,
                        outputSha256 = artifact.outputSha256,
                        dexEntryCount = artifact.dexEntryCount,
                        elapsedMillis = elapsedMillis(),
                    ),
                )
            },
            dispatch = { payload ->
                dispatchCallback("completed") { callback.onCompleted(payload) }
            },
        )
    }

    private fun finishContractError(error: DexCompilerContractException) {
        val (code, phase) = when (error.violation) {
            DexCompilerContractViolation.PROTOCOL_INCOMPATIBLE ->
                DexCompilerErrorCode.UNSUPPORTED_PROTOCOL to DexCompilerFailurePhase.NEGOTIATION
            DexCompilerContractViolation.CAPABILITY_INCOMPATIBLE ->
                DexCompilerErrorCode.UNSUPPORTED_CAPABILITY to DexCompilerFailurePhase.NEGOTIATION
            else -> DexCompilerErrorCode.INVALID_REQUEST to DexCompilerFailurePhase.INPUT_VALIDATION
        }
        finishError(requestIdHint, code, phase, error.message ?: "Compile request is incompatible")
    }

    private fun finishError(
        requestId: DexRequestId,
        code: DexCompilerErrorCode,
        phase: DexCompilerFailurePhase,
        message: String,
        diagnostics: Collection<DexCompilerDiagnostic> = emptyList(),
    ) {
        terminalController.dispatchTerminal(
            encode = {
                DexCompilerCodec.encodeError(
                    DexCompileError(
                        requestId = requestId,
                        code = code,
                        phase = phase,
                        message = boundedErrorMessage(message),
                        retryable = code == DexCompilerErrorCode.BUSY,
                        diagnostics = diagnostics,
                    ),
                )
            },
            dispatch = { payload ->
                dispatchCallback("failed") { callback.onFailed(payload) }
            },
        )
    }

    private fun finishCancellation(reason: DexCompilerCancellationReason) {
        terminalController.dispatchTerminal(
            stopWorkAfterDispatch = true,
            encode = {
                DexCompilerCodec.encodeCancellation(
                    DexCompileCancellation(
                        requestId = requestIdHint,
                        reason = reason,
                        phase = DexCompilerFailurePhase.CLEANUP,
                        elapsedMillis = elapsedMillis(),
                    ),
                )
            },
            dispatch = { payload ->
                dispatchCallback("cancelled") { callback.onCancelled(payload) }
            },
        )
    }

    private fun dispatchCallback(label: String, block: () -> Unit) {
        callbackLane.dispatch(label, block, ::callbackFailed)
    }

    private fun callbackFailed(@Suppress("UNUSED_PARAMETER") error: Throwable) {
        abortAndCleanupIfNoWorker()
    }

    private fun callbackDied() {
        abortAndCleanupIfNoWorker()
    }

    private fun linkCallbackDeath(): Boolean {
        if (!callbackDeathLinked.compareAndSet(false, true)) return !terminalController.isTerminal
        try {
            callbackBinder.linkToDeath(callbackDeathRecipient, 0)
        } catch (_: RemoteException) {
            callbackDeathLinked.set(false)
            callbackDied()
            return false
        }
        if (!callbackBinder.isBinderAlive) {
            callbackDied()
            return false
        }
        return true
    }

    private fun unlinkCallbackDeath() {
        if (!callbackDeathLinked.compareAndSet(true, false)) return
        try {
            callbackBinder.unlinkToDeath(callbackDeathRecipient, 0)
        } catch (error: VirtualMachineError) {
            throw error
        } catch (_: Throwable) {
            Unit
        }
    }

    private fun cleanup() {
        terminalController.cleanupOnce()
    }

    private fun abortAndCleanupIfNoWorker() {
        if (workScheduled.get()) {
            terminalController.abort()
        } else {
            terminalController.abortWithoutWorker()
        }
    }

    private fun cleanupResources() {
        try {
            descriptors.close()
        } finally {
            try {
                workspace?.close()
            } finally {
                workspace = null
                try {
                    unlinkCallbackDeath()
                } finally {
                    onFinished(this)
                }
            }
        }
    }

    private fun stopWork() {
        try {
            descriptors.close()
        } finally {
            workerThread.get()?.interrupt()
        }
    }

    private fun ensureActive() {
        if (terminalController.isTerminal || Thread.currentThread().isInterrupted) throw SessionStopped()
    }

    private fun elapsedMillis(): Long = (SystemClock.elapsedRealtime() - createdAtMillis).coerceAtLeast(0L)

    private fun boundedErrorMessage(message: String): String {
        val nonBlank = message.takeIf(String::isNotBlank) ?: "DEX compiler failure"
        val count = nonBlank.codePointCount(0, nonBlank.length)
        if (count <= MAX_ERROR_MESSAGE_CODE_POINTS) return nonBlank
        return nonBlank.substring(0, nonBlank.offsetByCodePoints(0, MAX_ERROR_MESSAGE_CODE_POINTS))
    }

    private class SessionStopped : RuntimeException()

    private companion object {
        const val MAX_ERROR_MESSAGE_CODE_POINTS = 512
        val ZERO_REQUEST_ID = DexRequestId.fromBytes(ByteArray(DexRequestId.BYTE_COUNT))
    }
}
