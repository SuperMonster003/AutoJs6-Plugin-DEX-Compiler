******

### Release history

******

# v1.0.0

###### 2026/08/08

* `Hint` First stable release. Inactive after installation by default; it must be enabled manually in the AutoJs6 developer options, see the "Installation and usage" section of the README for the steps
* `Feature` Acts as an external DEX compiler plugin for AutoJs6: when scripts load a JAR via `runtime.loadJar()`, this plugin can perform the JAR-to-DEX compilation in place of the built-in compiler
* `Feature` Compilation runs in a private sandbox inside the plugin's own process, isolated from AutoJs6; if the plugin fails or is unavailable, AutoJs6 falls back to its built-in compiler at most once
* `Feature` Strictly validates the input JAR's size, SHA-256, ZIP structure, entry names and class content before compiling, rejecting malformed, oversized or tampered input
* `Feature` Supports DEBUG and RELEASE compilation modes, multi-dex output and minApi 24 through 36; the output is a contiguously numbered `classes*.dex` ZIP reported with its actual size and SHA-256
* `Feature` Compatible with devices on Android 7.0 (API 24) and higher; API 26+ uses D8Command while API 24/25 automatically use a D8 CLI compatibility path
* `Feature` Communicates only with an identically signed AutoJs6 (protected by the `org.autojs.permission.PLUGIN` permission) and requests no network or storage permissions
* `Feature` Pure JVM implementation with a single universal APK covering all device architectures; ships with UI, README and in-app instructions in 10 languages
* `Fix` Accepts standard bounded ZIP/JAR archive comments when the declared length ends exactly at the file boundary, while still rejecting ambiguous EOCD records, inconsistent lengths and trailing data
* `Fix` Keeps the embedded D8 engine and its service providers intact in minified Release builds so production APKs can compile JAR inputs
* `Dependency` Bundles the Google R8 library 8.13.17 (providing the D8 compiler)
