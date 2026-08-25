# AutoJs6 DEX Compiler

This plugin lets AutoJs6 compile JAR files with D8 8.13.22 in a separate process. It supports `runtime.loadJar()` and the ordered compile-time classpath used by `runtime.loadJarWithClasspath()`.

## Before you enable it

- The plugin is disabled by default. Installing its APK does not change AutoJs6 behavior.
- AutoJs6 build 5270 or later and Android 7.0 (API 24) or later are required. The classpath entry point requires a newer paired host build.
- AutoJs6 and the plugin must have identical signatures. A mismatched plugin cannot be selected.

## Enable the plugin

1. Install or upgrade the compatible AutoJs6 host, then install this plugin APK.
2. In AutoJs6, open Settings > About app and developer, then long-press the app icon to enter the developer options.
3. Open DEX compiler > Raw JAR compiler provider.
4. Select this plugin's service component and confirm.

The provider summary means the plugin is selected; a particular load may still use a cached result or the built-in fallback.

## Use and recovery

Call `runtime.loadJar()` or `runtime.loadJarWithClasspath()` normally. The plugin adds no JavaScript global and cannot read the original script path.

If the plugin is unavailable, busy, times out, fails compilation, or returns invalid output, AutoJs6 retries the same request with its built-in compiler at most once. A deliberate cancellation does not trigger fallback. To disable the plugin, select Built-in D8/dx on the same developer-options page and restart AutoJs6; uninstalling the host or clearing its data is unnecessary.

## Safety and limits

- Only the same-signature AutoJs6 host may bind the compiler service.
- Input size, SHA-256, ZIP framing, entry paths, compression ratios, and class files are checked before compilation; AutoJs6 independently checks the returned DEX ZIP before caching or loading it.
- Output is limited to 16 MiB and 64 contiguous `classes*.dex` entries.
- The plugin requests no storage or network permission. It performs D8 compilation only, not R8 shrinking or obfuscation.

When reporting a problem, include the AutoJs6 build, plugin version, Android API, device ABI, reproduction steps, and the full script error. Remove private paths or sensitive content from logs before sharing them.
