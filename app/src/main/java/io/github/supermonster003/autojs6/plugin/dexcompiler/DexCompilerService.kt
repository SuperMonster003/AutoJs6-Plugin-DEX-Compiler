package io.github.supermonster003.autojs6.plugin.dexcompiler

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.os.ParcelFileDescriptor
import io.github.supermonster003.autojs6.plugin.dexcompiler.service.HostCallerVerifier
import io.github.supermonster003.autojs6.plugin.dexcompiler.service.OwnedParcelFileDescriptors
import io.github.supermonster003.autojs6.plugin.dexcompiler.service.RemoteDexCompileSession
import io.github.supermonster003.autojs6.plugin.dexcompiler.service.SerialCallbackLane
import org.autojs.plugin.dexcompiler.api.DexCompilerCodec
import org.autojs.plugin.dexcompiler.api.IDexCompilerCallback
import org.autojs.plugin.dexcompiler.api.IDexCompilerProvider
import org.autojs.plugin.dexcompiler.api.IDexCompilerSession
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

private val processSessionGate = SingleActiveSessionGate<RemoteDexCompileSession>()

class DexCompilerService : Service() {
    private lateinit var callerVerifier: HostCallerVerifier
    private lateinit var worker: ExecutorService
    private lateinit var callbackLane: SerialCallbackLane
    private val sessions = ConcurrentHashMap.newKeySet<RemoteDexCompileSession>()
    private val runtimeLibraries by lazy(LazyThreadSafetyMode.SYNCHRONIZED, RuntimeLibrarySet::discover)
    private val capabilities by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        DexCompilerRuntime.capabilities(runtimeLibraries)
    }

    override fun onCreate() {
        super.onCreate()
        callerVerifier = HostCallerVerifier(this)
        worker = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "dex-compiler-worker").apply { isDaemon = true }
        }
        callbackLane = SerialCallbackLane()
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onDestroy() {
        sessions.toList().forEach(RemoteDexCompileSession::serviceDestroyed)
        sessions.clear()
        worker.shutdown()
        callbackLane.close()
        super.onDestroy()
    }

    private val binder = object : IDexCompilerProvider.Stub() {
        override fun getCompilerInfo(): ByteArray {
            callerVerifier.enforceAllowedCaller()
            return DexCompilerCodec.encodeInfo(DexCompilerRuntime.info(this@DexCompilerService))
        }

        override fun getCapabilities(): ByteArray {
            callerVerifier.enforceAllowedCaller()
            return DexCompilerCodec.encodeCapabilities(this@DexCompilerService.capabilities)
        }

        override fun openSession(
            request: ByteArray?,
            programFd: ParcelFileDescriptor?,
            outputFd: ParcelFileDescriptor?,
            callback: IDexCompilerCallback?,
        ): IDexCompilerSession {
            val ownerUid = try {
                callerVerifier.enforceAllowedCaller()
            } catch (error: Throwable) {
                OwnedParcelFileDescriptors.closeIncoming(programFd, outputFd)
                throw error
            }
            if (request == null || programFd == null || outputFd == null || callback == null) {
                OwnedParcelFileDescriptors.closeIncoming(programFd, outputFd)
                throw IllegalArgumentException("DEX compiler session arguments must not be null")
            }
            val descriptors = OwnedParcelFileDescriptors.duplicateBeforeAsync(programFd, outputFd)
            val session = try {
                RemoteDexCompileSession(
                    context = applicationContext,
                    ownerUid = ownerUid,
                    requestMetadata = request.copyOf(),
                    descriptors = descriptors,
                    callback = callback,
                    capabilities = this@DexCompilerService.capabilities,
                    runtimeLibraries = runtimeLibraries,
                    callerVerifier = callerVerifier,
                    worker = worker,
                    callbackLane = callbackLane,
                    onFinished = { finished ->
                        processSessionGate.release(finished)
                        sessions.remove(finished)
                    },
                )
            } catch (error: Throwable) {
                descriptors.close()
                throw error
            }

            sessions += session
            if (processSessionGate.tryAcquire(session)) {
                session.start()
            } else {
                session.rejectBusy()
            }
            return session
        }
    }
}
