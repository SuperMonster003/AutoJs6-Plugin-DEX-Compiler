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

> The current AutoJs6 DEX adapter remains a default-off experimental feature and is not connected to AndroidClassLoader. Installing this plugin alone does not replace the existing default JAR-to-DEX path. End-to-end use requires a future host adapter or explicit host enablement and selection of this compiler provider.

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
