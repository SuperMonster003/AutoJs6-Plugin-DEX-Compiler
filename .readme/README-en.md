<!--suppress HtmlDeprecatedAttribute, HttpUrlsUsage -->

<div align="center">
  <p>
    <img src="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/res/mipmap/ic_launcher.png?raw=true" alt="dex-compiler-ic-launcher" border="0" width="128" />
  </p>

  <p>Standalone DEX compiler plugin for AutoJs6. Compiles script JARs into DEX with an up-to-date D8 in an isolated process</p>

  <p>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/releases"><img alt="GitHub release (latest by date)" src="https://img.shields.io/github/v/release/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?label=Release"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/issues"><img alt="GitHub closed issues" src="https://img.shields.io/github/issues/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=A24232&label=Issues"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/LICENSE"><img alt="GitHub License" src="https://img.shields.io/github/license/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=534BAE&label=License"/></a>
  </p>
</div>

******

### Languages

******

The README.md file is currently available in the following languages:

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

AutoJs6 scripts can load a JAR with `runtime.loadJar()` and call the Java classes inside it. Since Android cannot run JVM bytecode directly, such JARs must first be compiled into DEX; by default, this step is handled by the compiler built into AutoJs6.

This plugin offers an alternative: it is a separately installed app that performs that compilation with a newer version of Google's D8 compiler, inside its own isolated process. AutoJs6 hands the JAR to the plugin, takes the DEX result back, then validates, caches and loads it on its own; if anything goes wrong with the plugin, AutoJs6 automatically falls back to its built-in compiler, so scripts usually keep working.

Install this plugin if you want a newer D8 than the one bundled with AutoJs6, want compilation to run in a process isolated from AutoJs6, or want to upgrade the compiler independently of AutoJs6 updates.

******

### How it works

******

With the plugin enabled, a `runtime.loadJar()` call roughly goes through the following steps:

```text
1. script     calls runtime.loadJar() or runtime.loadJarWithClasspath()
2. AutoJs6    validates and freezes the input JAR, records its size and SHA-256
3. plugin     re-verifies the input, then compiles it with D8 in a private sandboxed process
4. plugin     returns a DEX ZIP (classes.dex, classes2.dex, ...)
5. AutoJs6    independently re-validates the result, caches it, and loads the classes
*  fallback   if anything fails, AutoJs6 retries once with its built-in compiler
```

The plugin is only responsible for steps 3 and 4, i.e. the compilation itself; freezing the input, validating the result, caching and the final class loading always stay inside AutoJs6. The two apps exchange nothing but file descriptors over Binder, so the plugin never reads your script directory and never learns the original file paths. Compiled results are cached by input content and compilation parameters, so loading the same JAR again hits the cache without recompiling.

******

### Features

******

- Compilation is performed by D8 8.13.22; the plugin can upgrade its compiler independently of AutoJs6.
- Compilation runs in the plugin's own process and private workspace, so crashes or failures never affect the AutoJs6 main process.
- Double validation: the plugin checks the JAR's size, SHA-256, ZIP structure and class content before compiling; AutoJs6 independently re-validates the DEX output afterwards.
- Supports DEBUG and RELEASE compilation modes, multi-dex output, and minApi 24 through 36 as compilation parameters.
- Supports every device running Android 7.0 (API 24) or higher; API 26+ uses D8Command, while API 24/25 automatically switch to a D8 CLI compatibility path.
- Protocol V1.1 supports an ordered compile-time classpath (`runtime.loadJarWithClasspath()`) for compiling JARs that reference external APIs.
- On any failure, AutoJs6 falls back to its built-in compiler at most once, so scripts never get stuck on the plugin.

******

### Installation and usage

******

Enabling the plugin takes three steps: install a compatible AutoJs6, install this plugin APK, then manually select the plugin in the AutoJs6 developer options. Two things to know up front:

- The plugin is inactive by default. Merely installing it changes nothing in AutoJs6; you must enable it manually as described below.
- It can be reverted at any time. Switching back to Built-in D8/dx in the developer options restores the original behavior without uninstalling anything.

#### Prerequisites

- AutoJs6 build 5270 or higher (for `runtime.loadJar()`); `runtime.loadJarWithClasspath()` requires a newer paired host build (build 5274 was used for verification).
- Host and plugin must come from the same trusted source and carry identical signatures. With mismatched signatures the plugin cannot be selected; use paired release packages or build both yourself, and never work around it by uninstalling the host or clearing its data.
- When building yourself, keep the fixed package names and service component below unchanged.
- Back up your scripts and important data before upgrading.

The relevant identifiers are:

```text
host package: org.autojs.autojs6
plugin package: io.github.supermonster003.autojs6.plugin.dexcompiler
minimum host build: 5270
exact component: io.github.supermonster003.autojs6.plugin.dexcompiler/io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerService
```

#### Install and enable

1. Install or upgrade to a compatible AutoJs6.
2. Install this plugin APK.
3. Open AutoJs6, go to Settings > About app and developer, and long-press the app icon to enter the developer options.
4. Go to DEX compiler > Raw JAR compiler provider.
5. Select this plugin's service component (the exact component shown above) and confirm.

To repeat: installing the plugin alone does not enable it, and AutoJs6 never auto-selects a discovered provider; steps 3 through 5 are required.

#### Confirm it is active

Return to the developer options page. When the summary shows this plugin's service component as selected, the plugin is active: from then on, compilation for `runtime.loadJar()` and `runtime.loadJarWithClasspath()` is preferentially handled by the plugin.

If the plugin does not appear in the list, or the summary still shows Built-in D8/dx, check in order: the AutoJs6 build is at least 5270; the host and plugin package names match the ones above; the plugin app is not disabled by the system; both signatures are identical.

Note: the summary tells you "who is currently selected", not "who actually performed a given compilation"; an individual compilation may still bypass the plugin due to a cache hit or a fallback (see below).

#### Script example

Place a JAR containing JVM `.class` files at `lib/example.jar` in your script directory, then call `runtime.loadJar()` as usual; the plugin adds no new JavaScript globals, and scripts are written exactly as with the built-in compiler. Replace the class name and method in the example with a public API that actually exists in your JAR.

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

If the JAR references classes that exist in the runtime environment but are not part of the JAR itself (for example API stubs), use the explicit compile-time classpath entry point:

```javascript
runtime.loadJarWithClasspath(
    files.path("./lib/program.jar"),
    files.path("./lib/compile-api-stubs.jar"),
);
```

Three things to know about the classpath:

- Classpath JARs are only used to resolve references at compile time; they are neither packaged into the output nor loaded automatically.
- If the program actually uses those classes at runtime, they must already exist in the parent chain of the final class loader (such as Android system classes or classes shipped with AutoJs6). Loading a dependency JAR with `runtime.loadJar()` first does not achieve this, as it only creates a sibling loader.
- The declared classpath order matters and is part of the cache identity; this entry point requires at least one classpath JAR.

Separately, `.aar` files, precompiled `.dex` files and dynamic entry points such as `defineClass()` are always handled by AutoJs6's built-in path and never involve this plugin. Finally, remember that compilation is not a security review: only load JARs you trust.

#### What happens when compilation fails

Even with the plugin enabled, AutoJs6 still puts "the script must keep running" first:

- `runtime.loadJar()`: if the plugin is unavailable, compilation fails, times out, or the output fails validation, AutoJs6 automatically recompiles the same JAR with the built-in D8/dx, at most once per request.
- `runtime.loadJarWithClasspath()`: the fallback is likewise at most once, and must hand the exact same program plus classpath to local D8; the classpath is never dropped and never silently downgraded.
- A deliberate cancellation (such as stopping the script) is not a failure: it does not trigger a fallback and simply ends the load.
- When the plugin returns BUSY (only one compilation session at a time), AutoJs6 applies the rules above; just retry the script a moment later.

As a consequence, a script running successfully does not prove that its compilation went through the plugin; when you need certainty, use the troubleshooting steps below.

#### Troubleshooting and reporting

If you suspect the plugin is misbehaving, first switch back to Built-in D8/dx and compare the behavior. When reporting an issue, please include as much of the following as possible:

- AutoJs6 build/version, plugin version, and the full component name from the developer options summary.
- Device model, Android version (API) and CPU architecture (ABI).
- The JAR that triggers the issue (or its byte size and SHA-256), the full script exception, and reproduction steps.

If you are comfortable with ADB, the following commands collect the relevant logs (replace `<serial>` with your device serial; strip private paths and sensitive content before sharing):

```powershell
adb -s <serial> shell dumpsys package org.autojs.autojs6
adb -s <serial> shell dumpsys package io.github.supermonster003.autojs6.plugin.dexcompiler
adb -s <serial> logcat -d -v threadtime AndroidClassLoader:D AndroidRuntime:E *:S
```

#### Disable, roll back and uninstall

- Temporarily disable: in the developer options under Raw JAR compiler provider, select Built-in D8/dx and confirm, then fully quit and restart AutoJs6. The component selection record is kept, so you can re-enable it at any time.
- In an emergency: disabling and restarting the host as above is sufficient; there is no need to uninstall AutoJs6, clear its data or delete scripts.
- Uninstall the plugin: switch back to Built-in D8/dx first, then stop AutoJs6 and uninstall the plugin APK. Uninstalling removes all of the plugin's own data and temporary files; AutoJs6 keeps working with its built-in compiler.
- After reinstalling, the plugin must be enabled manually again; the previous selection is not restored automatically.

******

### FAQ

******

**Q: I installed the plugin and nothing changed. Is it broken?**

A: No. The plugin is disabled by default and must be enabled manually in the developer options (see above); it also only affects the compilation step of `runtime.loadJar()` and `runtime.loadJarWithClasspath()`, nothing else in your scripts.

**Q: How can I confirm that a compilation was really done by the plugin?**

A: The developer options summary only means "the plugin is selected". Because failures fall back automatically and results are cached, a successful script does not imply the plugin compiled it; collect logs as described under "Troubleshooting and reporting".

**Q: Will this plugin make my scripts faster?**

A: Its goals are a newer compiler, stricter input validation and process isolation, not performance. Compilation takes roughly as long as with the built-in compiler, and compiled results are cached by AutoJs6.

**Q: Does the plugin support R8 shrinking/obfuscation? Is RELEASE mode R8?**

A: No and no. This plugin only performs D8 compilation; `RELEASE` merely selects D8's release compilation mode and involves no shrinking, obfuscation or mapping. R8 capabilities belong to a separate, independent provider plugin.

**Q: Why must the host and the plugin have identical signatures?**

A: It is a mutual security check: it stops other apps from impersonating AutoJs6 towards the plugin, and stops a tampered plugin from impersonating the compilation service. On a mismatch, switch to paired release packages instead of uninstalling or clearing data.

**Q: Does the plugin access the network or my files?**

A: No. The plugin has no network or storage permissions; it can only read the content handed over by AutoJs6 through file descriptors, and its temporary files live entirely in its own private directory.

******

### Scope boundaries

******

To avoid misunderstandings, the following are explicitly outside this plugin's scope:

- No R8 shrinking, optimization or obfuscation, and no mapping files; `RELEASE` only selects D8's release compilation mode.
- No dependency downloading or resolution (no Maven/Gradle integration), and no network compilation.
- No handling of `.aar` files, precompiled `.dex` files or dynamic `defineClass()` bytecode; those always take AutoJs6's built-in path.
- The V1.1 classpath is compile-only: it does not bundle runtime dependencies and does not create combined class loaders.
- No byte-level deterministic output guarantee: the same input may produce different but equivalent DEX across compiler versions.
- No replacement for AutoJs6's output validation: the host always re-validates the DEX result independently.
- Never becomes the default compiler automatically: enabling it is always an explicit user decision.

******

### Technical reference

******

The following sections target developers and integrators who need precise boundaries; regular plugin users can usually skip them.

#### Input and output

Protocol V1.0 receives one raw program JAR through an input descriptor; V1.1 receives one program JAR plus at least one ordered compile-time classpath JAR inside the same bounded input bundle. Both produce output of the same form:

```text
input: JAR with JVM class files
output: DEX ZIP with contiguous classes*.dex entries
compiler: D8 8.13.22
```

#### Plugin discovery identifiers

The host discovers and invokes the plugin through the following identifiers:

```text
service action: org.autojs.plugin.DEX_COMPILER
plugin id: dex-compiler
protocol provider id: autojs6-d8
engine: dex-compiler
variant: d8
protocol: V1
required host build: 5270
```

The plugin declares D8 8.13.22, protocol range V1.0 through V1.1, JAR input, DEX ZIP output, DEBUG and RELEASE modes, minApi 24 through 36, and multi-dex; the runtime library model is device boot classpath V1.

Build 5270 is the minimum host requirement for V1.0; `runtime.loadJarWithClasspath()` requires a paired host build with V1.1 support (build 5274 was used for representative verification). The plugin contains no native libraries and covers all device ABIs with a single pure-JVM universal APK.

#### Security model

The plugin requests no network or storage permissions. The compilation service is protected by the `org.autojs.permission.PLUGIN` permission, and every call verifies the AutoJs6 package name, the calling UID and both parties' signatures. Inputs and outputs travel as file descriptors and are copied before asynchronous processing; temporary files live only in the plugin's private cache and are cleaned up after compilation ends.

#### Resource limits

To defend against malicious or malformed input, the plugin enforces hard limits at every stage; requests exceeding them are rejected outright:

- Input JAR: at most 64 MiB compressed, 20000 entries, and 256 MiB total decompressed data.
- V1.1 classpath: at most 32 JARs, 64 MiB per compressed JAR, 128 MiB total compressed classpath, and 256 MiB for the whole input bundle.
- Class data: at most 128 MiB in total and 8 MiB per class; per-entry and overall compression ratios are also bounded.
- Output DEX ZIP: at most 16 MiB with at most 64 contiguously numbered DEX entries; requests may declare lower ceilings.
- Concurrency: only one active compilation session per process; additional requests receive a retryable BUSY error.
- Diagnostics are capped at 64 KiB, with separate caps on error text and the callback queue.

#### Caveats

- Cancelling or closing immediately blocks result publication and interrupts the worker, but D8's internal CPU work cannot be reliably stopped and may continue in the isolated process until the current compilation returns.
- After a cancellation, the session slot stays occupied until the worker actually exits and cleanup completes; new requests receive BUSY in the meantime.
- The plugin claims no deterministic output; the cache identity includes the compiler version and runtime fingerprint, so version changes never reuse stale results.
- V1.1 only accepts the compile-time classpath frozen and bundled by the host; it accepts no caller file paths and no custom desugared library configuration.
- The device runtime boot classpath varies across systems; requests must match the runtime fingerprint reported by the provider.

******

### Development roadmap

******

Development proceeds in stages, and R0 through R5 are complete within the currently authorized scope with reviewable evidence. The R5.2 bounded-parallelism candidate remains `NOT_PROMOTED` because all three corrected process-cold cache-hit added-P95 latency cells exceed 100 ms. R5.3 froze v1.1.0 with D8 8.13.22, passed representative real-provider classpath cells on API 24/x86, API 34/x86_64 and API 35/arm64, and found zero cross-directory output-digest differences across 54 output-producing cells while retaining `determinismClaim=NOT_CLAIMED`. R5.4 is closed by an explicit owner decision: the existing independent R8 provider prerelease was converted to a non-prerelease Release while its repository remains Private; making the repository public, publicly releasing paired AutoJs6 build 5276, and registering the official plugin index were not performed and are deferred together to a future independent R8 G9 Public Gate. This is not a public release and does not change the plugin's default-off status. For per-item definitions of done and evidence, see:

- [Open the checkable ROADMAP.md](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/ROADMAP.md)

******

### Release history

******

# v1.1.2

###### 2026/09/15

* `Fix` Resolve the D8 test matrix android.jar through AGP and defer reading the boot classpath until task execution to avoid build failures when Test tasks are created early
* `Improvement` Raise compileSdk and targetSdk to 37 (Android 17); the plugin's behavior does not depend on the new target

# v1.1.1

###### 2026/09/13

* `Fix` Keep the plugin version date in English regardless of the build machine locale
* `Improvement` Consistent localized resources, explicit plugin activation and validated release preparation

# v1.1.0

###### 2026/09/11

* `Hint` `runtime.loadJarWithClasspath()` requires a paired AutoJs6 build 5274 or newer; ordinary `runtime.loadJar()` remains compatible with build 5270 or newer
* `Feature` Adds V1.1 ordered compile-time classpath support: a program JAR may reference external API JARs, while classpath inputs are used only for compilation and are neither packaged into DEX nor loaded automatically
* `Fix` Accepts standard bounded ZIP/JAR archive comments when the declared length ends exactly at the file boundary, while still rejecting ambiguous EOCD records, inconsistent lengths and trailing data
* `Fix` Keeps the embedded D8 engine and its service providers intact in minified Release builds so production APKs can compile JAR inputs
* `Improvement` Reports bounded, privacy-safe D8 info/warning/error diagnostics with available source, archive entry and position metadata to make plugin compilation failures easier to investigate
* `Improvement` Limits D8's internal parallel compilation to two worker threads to reduce peak memory for large cold JARs without changing output or cache semantics
* `Improvement` Build verification rejects accidental native dependencies and produces a JSON report
* `Dependency` Upgrades the bundled Google R8 library to 8.13.22 (providing the D8 compiler)

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

Build parameters come from `version.properties`. The current minimum SDK is 24, the target SDK is 36, the minimum JDK is 17 and JDK 21 is recommended.

The protocol ABI is provided by local AARs in the repository `libs` directory:

```text
common-plugin-api.aar
protocol-wire-api.aar
dex-compiler-api.aar
```

The compiler is pulled in through Maven as D8 8.13.22. The local AARs only provide the stable protocol boundary, and the build output is a universal APK without native libraries.

******

### License

******

The project source code is licensed under MPL-2.0. R8 and other third-party components remain subject to their own licenses.

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

`.python/generate_markdown.py` generates the README and in-app changelog for all 10 languages from the JSON sources; to change the documentation, edit the JSON sources rather than the generated Markdown. Android UI strings are managed in their respective resource directories.

******

### Links

******

- AutoJs6 documentation: https://docs.autojs6.com
- R8 project: https://r8.googlesource.com/r8


[16 KB page alignment and build verification](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/docs/16kb.md)
