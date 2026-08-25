package io.github.supermonster003.autojs6.plugin.dexcompiler

import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import org.autojs.plugin.common.api.IPluginInfoProvider
import org.autojs.plugin.common.api.PluginCapabilityKeys
import org.autojs.plugin.common.api.PluginInfo
import org.autojs.plugin.dexcompiler.api.DexCompilerContract
import org.autojs.plugin.dexcompiler.api.DexCompilerFamily
import java.util.Locale

internal val D8_PLUGIN_FAMILY_ID: String = DexCompilerFamily.D8.name.lowercase(Locale.ROOT)

class DexCompilerPluginInfoService : Service() {
    private val binder = object : IPluginInfoProvider.Stub() {
        override fun getInfo(): PluginInfo {
            val packageInfo = packageManager.getPackageInfo(packageName, 0)
            val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageInfo.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                packageInfo.versionCode.toLong()
            }
            return PluginInfo(
                name = getString(R.string.app_name),
                description = getString(R.string.plugin_description),
                instruction = resources.openRawResource(R.raw.plugin_instruction)
                    .bufferedReader()
                    .use { it.readText() },
                author = getString(R.string.plugin_author),
                collaborators = null,
                versionName = packageInfo.versionName.orEmpty(),
                versionCode = versionCode,
                versionDate = getString(R.string.plugin_version_date),
                id = DexCompilerRuntime.PLUGIN_ID,
                engine = DexCompilerContract.ENGINE_ID,
                variant = DexCompilerRuntime.PLUGIN_VARIANT,
                supportedAbis = emptyArray(),
                capabilities = Bundle().apply {
                    putLong(PluginCapabilityKeys.REQUIRES_HOST_VERSION, DexCompilerRuntime.REQUIRED_HOST_VERSION)
                    putInt("dexCompilerProtocolMajor", DexCompilerContract.PROTOCOL_MAJOR)
                    putInt("dexCompilerProtocolMinor", DexCompilerContract.PROTOCOL_MINOR)
                    putString("compilerFamily", D8_PLUGIN_FAMILY_ID)
                    putString("compilerVersion", DexCompilerRuntime.COMPILER_VERSION)
                },
            )
        }
    }

    override fun onBind(intent: Intent?): IBinder = binder
}
