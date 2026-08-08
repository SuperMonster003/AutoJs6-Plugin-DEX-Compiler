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
