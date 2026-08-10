<!--suppress HtmlDeprecatedAttribute, HttpUrlsUsage -->

<div align="center">
  <p>
    <img src="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/res/mipmap/ic_launcher_dex.png?raw=true" alt="dex-compiler-ic-launcher" border="0" width="128" />
  </p>

  <p>Independent DEX compiler plugin. Compile validated JARs into a contiguous classes*.dex ZIP with D8</p>

  <p>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/releases"><img alt="GitHub release (latest by date)" src="https://img.shields.io/github/v/release/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?label=Release"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/issues"><img alt="GitHub closed issues" src="https://img.shields.io/github/issues/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=A24232&label=Issues"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/LICENSE"><img alt="GitHub License" src="https://img.shields.io/github/license/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=534BAE&label=License"/></a>
  </p>
</div>

******

### Languages

******

The current README.md supports the following languages:

- [简体中文 [zh-Hans]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hans.md)
- [繁體中文 (香港) [zh-Hant-HK]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hant-HK.md)
- [繁體中文 (台灣) [zh-Hant-TW]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hant-TW.md)
- English [en] # current
- [Français [fr]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-fr.md)
- [Español [es]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-es.md)
- [日本語 [ja]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ja.md)
- [한국어 [ko]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ko.md)
- [Русский [ru]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ru.md)
- [العربية [ar]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ar.md)

******

### Introduction

******

DEX Compiler is an independent provider for version 1 of the AutoJs6 DEX Compiler protocol. It uses D8 in an app-private workspace to compile a strictly validated JVM JAR and returns a canonical DEX ZIP through an output descriptor supplied by the host.

******

### Features

******

- Accept JAR input in DEBUG or RELEASE mode with minApi 24 through 36 and multi-dex output.
- Verify declared size and SHA-256, ZIP framing, entry names, class magic, duplicates, and decompression bounds before compilation.
- Compile against the device runtime boot classpath and its fingerprint without accepting an external classpath.
- Package only contiguous `classes.dex`, `classes2.dex`, and later DEX files and report the actual ZIP size and SHA-256.
- Use D8Command on Android API 26 and later and the D8 CLI fallback on API 24 and 25.

******

### Input and output formats

******

Version 1 declares only the following compilation scope:

```text
input: JAR with JVM class files
output: DEX ZIP with contiguous classes*.dex entries
compiler: D8 8.13.17
```

******

### Plugin interface

******

The host discovers and calls the plugin with the following identities:

```text
service action: org.autojs.plugin.DEX_COMPILER
plugin id: dex-compiler
protocol provider id: autojs6-d8
engine: dex-compiler
variant: d8
protocol: V1
required host build: 5270
```

The plugin declares D8 8.13.17, JAR input, DEX ZIP output, DEBUG and RELEASE modes, minApi 24 through 36, and multi-dex. Its runtime library model is device boot classpath V1.

Host build 5270 or later is required. The plugin has no native library, so one pure JVM universal APK supports every device ABI.

******

### Host integration status

******

> The raw runtime.loadJar route remains default-off and requires an explicitly selected same-signed exact component. Production Runtime single-flight coalescing uses the bounded persistent semantic cache after authenticated key finalization. Interrupting any waiter, including the last, detaches only that caller without local fallback; the producer may finish and cache the result. Cooperative last-waiter cancellation remains R2, and an opened safety circuit stays conservative for the process lifetime. API 31 arm64 real-provider tests now cover committed remote dispatch, Binder lifecycle, and the specified DexClassLoader corpus, completing R1.2 only; R1.1 and the multi-API/ABI matrix remain open.

******

### R1 installation and usage guide

******

> This is a default-off R1 explicit opt-in path, not a compiler replacement that activates when installed. The R1.3 multi-API/ABI matrix is still open; canonical real-provider device evidence currently covers API 31 arm64 only, so the protocol range of minApi 24 through 36 must not be read as acceptance on every device.

#### Prerequisites

Obtain AutoJs6 and the plugin only from a trusted, paired release source. AutoJs6 must be build 5270 or later, and the complete current signer sets of host and plugin must match; self-built artifacts must also keep the fixed package and service identities below. Back up scripts and important app data before upgrading. If Android reports a signer mismatch, do not work around it by uninstalling the host or clearing its data.

```text
host package: org.autojs.autojs6
plugin package: io.github.supermonster003.autojs6.plugin.dexcompiler
minimum host build: 5270
exact component: io.github.supermonster003.autojs6.plugin.dexcompiler/io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerService
```

#### Install and explicitly enable

Install or update the compatible AutoJs6 first, then install the plugin APK. In AutoJs6, open Settings > About app and developer and long-press the app icon to open Developer options. Open DEX compiler > Raw JAR compiler provider, select the exact component below, and confirm. Installing the plugin alone does not enable the route, and AutoJs6 never automatically selects a discovered provider.

#### Confirm status

Return to Developer options and confirm that the summary explicitly says raw runtime.loadJar JARs prefer the exact component below. If it shows Built-in D8/dx or no candidate, verify the host build, both package names, plugin enabled state, and signatures. The summary proves only current selection and discovery eligibility; it does not prove that a particular compile was remote or that R1.3 is complete.

#### AutoJs6 example

Place a readable JAR containing JVM `.class` files at `lib/example.jar` beside the script, then replace the sample class and method with a real public API in that JAR. The script uses the selected provider through the existing `runtime.loadJar()` entry; the plugin adds no new JavaScript global.

```javascript
"use strict";

const jar = files.path("./lib/example.jar");
if (!files.isFile(jar)) {
    throw new Error("Missing JAR: " + jar);
}

runtime.loadJar(jar);

// Replace this with a public class that actually exists in example.jar.
const Example = Packages.com.example.autojs6.DexPluginExample;
console.log("DEX compiler example: " + Example.answer());
```

This example covers raw JARs only. `.aar`, precompiled `.dex`, compatibility helpers, and dynamic `defineClass()` always stay on host built-in paths. Validation does not make untrusted bytecode safe; load only JARs you trust.

#### Collect diagnostics

For a problem report, record the AutoJs6 build/version, plugin version, full exact-component summary from Developer options, device model/API/ABI, input JAR byte count and SHA-256, event time, complete script exception, and reproduction steps. If using ADB, put the one authorized device ID in `<serial>` on every command, capture AndroidClassLoader/AndroidRuntime logs around the failure, and remove private paths, script content, and other sensitive data before sharing.

```powershell
adb -s <serial> shell dumpsys package org.autojs.autojs6
adb -s <serial> shell dumpsys package io.github.supermonster003.autojs6.plugin.dexcompiler
adb -s <serial> logcat -d -v threadtime AndroidClassLoader:D AndroidRuntime:E *:S
```

#### Disable and emergency rollback

In Developer options > Raw JAR compiler provider, select Built-in D8/dx and confirm, then stop and restart AutoJs6. This turns off the experimental route while retaining the selected-component record for later reselection. For an emergency rollback, disable first and restart the host; there is no need to uninstall AutoJs6, clear its data, or delete scripts. An opened process safety circuit intentionally remains open until that AutoJs6 process ends.

#### Understand fallback

When the route is off, the provider is unavailable or incompatible, binding or remote work fails, a timeout occurs, output is invalid, or adoption of a verified artifact fails, one invocation may make at most one host built-in D8/dx attempt; dispatched Binder work is not automatically retried. Caller cancellation or thread interruption propagates with no local fallback. AAR, loadDex, and defineClass never use this plugin. Therefore, a script that ultimately succeeds proves only that some permitted path succeeded, not that the plugin compiled it.

#### Uninstall and recover

Select Built-in D8/dx first, confirm that the summary shows the experiment off, then stop AutoJs6 and uninstall the plugin. Uninstall permanently removes the plugin's own app data and private temporary workspaces, while the host can continue with its built-in compiler. To recover, install a compatible same-signed plugin, reopen Developer options, and explicitly select the exact component again; do not assume the old selection automatically becomes enabled.

#### Known limits and acceptance boundary

V1 performs only bounded raw JVM JAR-to-DEX-ZIP conversion. It provides no R8 shrinking or obfuscation, external classpath, custom desugared library, network compilation, or deterministic byte output. BUSY may lead to host fallback, and D8 CPU work may continue in the isolated process until cleanup after cancellation. API 31 arm64 R1.2 evidence does not replace R1.1 production fault/rollback gates or the R1.3 API 24/25/26/28/34/36 and x86_64/arm64 matrix; treat this guide as a controlled preview until those boxes are checked.

******

### Development roadmap

******

R1.2 is 4/4: 16 host DEX suites/149 tests passed, Android-test Kotlin and host/test APK assembly succeeded, and API 31 arm64 passed two production-concurrency, two real-lifecycle, and three real-corpus methods. The concurrency probe counts committed remote dispatch rather than direct provider openSession calls; the separate heavy multi-dex gate generated 65,700 methods and loaded classes from primary and secondary DEX. Current host/test/plugin SHA-256 prefixes are 181E38E8, 70FAE1E8, and 5B6AC53B with the same 31a681fc signer. Final host/test/plugin uninstalls succeeded, the fake provider remained absent, and the related process count was zero. R1.1 remains 0/7 and R1.3 remains fully open. R2 has started only a recovery slice: the process-once strict-canonical janitor passed plugin 48/48 and workspace recovery 6/6, removed a real force-stop stale UUID before first Binder exposure, and kept the workspace empty after a normal D8 load; broader R2 items remain unchecked.

- [Open the checkable ROADMAP.md](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/ROADMAP.md)

******

### Security

******

The plugin requests no network or storage permission. The compiler service is protected by `org.autojs.permission.PLUGIN` and verifies the AutoJs6 package name, calling UID ownership, and matching signatures. Input and output descriptors are duplicated before asynchronous work. Temporary files stay in app-private cache and are removed after the worker exits.

******

### Operational limits

******

- Compressed JAR input is limited to 64 MiB and 20000 entries, with 256 MiB of total uncompressed data.
- Class data is limited to 128 MiB in total and 8 MiB per class. Entry and aggregate compression ratios are bounded.
- A DEX ZIP is limited to 16 MiB and 64 contiguously indexed DEX entries. A request may choose a lower output ceiling.
- At most one compilation session is active in the process. Busy requests receive a retryable BUSY error.
- Diagnostics are limited to 64 KiB. Error text and the callback queue have separate bounds.

******

### Limitations and caveats

******

- Cancel or close immediately prevents result publication, closes descriptors, and interrupts the worker, but D8 CPU work cannot be interrupted reliably.
- After cancellation, the session slot remains occupied until the D8 worker actually exits and cleanup completes. New requests receive BUSY meanwhile.
- The plugin makes no determinism claim and accepts neither an external classpath nor a custom desugared library configuration.
- The host still revalidates output with its complete DexIndexedZipValidator. Plugin packaging checks do not replace host validation.
- The device runtime boot classpath may vary by system. A request must match the runtime fingerprint reported by the provider.

******

### Release history

******

# v1.0.0

###### 2026/08/08

* `Feature` DEX Compiler protocol V1 provider with plugin ID and engine `dex-compiler`, provider ID `autojs6-d8`, and variant `d8`
* `Feature` JAR to DEX ZIP compilation with DEBUG, RELEASE, minApi 24 through 36, multi-dex, and a device runtime boot classpath fingerprint
* `Feature` Bounded JAR size, entry count, decompressed data, class data, diagnostics, and output with strict ZIP framing, name, and class magic validation
* `Feature` Contiguous `classes*.dex` packaging with actual size and SHA-256 reporting plus host revalidation through DexIndexedZipValidator
* `Feature` One active session, same-signature AutoJs6 caller checks, a private workspace, API 24 and 25 CLI fallback, and conservative cancellation semantics
* `Feature` One pure JVM universal APK plus README, changelog, Android UI, and plugin instructions in 10 languages
* `Dependency` Added R8 8.13.17 for D8 compilation

##### For more releases

* [CHANGELOG-en.md](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/assets/doc/CHANGELOG-en.md)

******

### Build

******

```powershell
.\gradlew.bat :app:assembleDebug
```

Release build:

```powershell
.\gradlew.bat :app:assembleRelease
```

Build parameters come from `version.properties`. The current minimum SDK is 24, the target SDK is 36, JDK 17 is the minimum, and JDK 21 is recommended.

The protocol ABI is supplied by repository-local AARs in `libs`:

```text
common-plugin-api.aar
protocol-wire-api.aar
dex-compiler-api.aar
```

The compiler uses D8 8.13.17 from Maven. Local AARs provide only the stable protocol boundary, and the resulting plugin is a universal APK without native libraries.

******

### License

******

Project source is licensed under MPL-2.0. R8 and other third-party components remain under their respective licenses.

******

### Resource layout

******

```text
.readme/lang_*.json
.changelog/lang_*.json
.python/generate_markdown.py
app/src/main/assets/doc/CHANGELOG-*.md
app/src/main/res/values-*/strings.xml
```

`.python/generate_markdown.py` generates README files and in-app changelogs in 10 languages from JSON sources. Android strings are maintained in their own resource directories.

******

### Links

******

- AutoJs6 documentation: https://docs.autojs6.com
- R8 project: https://r8.googlesource.com/r8
