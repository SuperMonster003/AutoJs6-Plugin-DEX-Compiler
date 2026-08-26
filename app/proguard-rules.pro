-dontwarn kotlinx.parcelize.Parcelize
-dontwarn javax.xml.stream.XMLInputFactory
-dontwarn javax.xml.stream.XMLStreamReader

-keep class io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerPluginInfoService { *; }
-keep class io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerService { *; }
-keep class io.github.supermonster003.autojs6.plugin.dexcompiler.WakeActivity { *; }
-keep class org.autojs.plugin.common.api.** { *; }
-keep class org.autojs.plugin.dexcompiler.api.** { *; }

# D8 is an embedded compiler, not an ordinary app library. Its implementation relies on stable
# internal names, metadata, and META-INF/services providers while constructing and running a
# compiler command. Keep the engine intact so Release packaging cannot remove those providers.
-keep class com.android.tools.r8.** { *; }

# These optional desktop/assistant paths ship in the R8 artifact but are never invoked by the
# Android D8 provider. They are absent from Android's boot class path by design.
-dontwarn com.android.tools.r8.keepanno.annotations.KeepForApi
-dontwarn com.sun.management.HotSpotDiagnosticMXBean
-dontwarn java.lang.management.ManagementFactory
-dontwarn javax.management.MBeanServer
-dontwarn javax.management.MBeanServerConnection
