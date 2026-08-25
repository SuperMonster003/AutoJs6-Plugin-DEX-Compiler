# R4.3 source and packaging responsibility boundary

This fail-closed static Gate proves the production DEX provider remains a validated-JAR-to-DEX
runtime. Java/Kotlin source compilation must happen in a separate compiler plugin or build layer and
must produce a class-bearing JAR before the DEX protocol can accept it.

The same Gate proves that AAR resource merging, APK packaging, APK signing, and APK installation are
not runtime capabilities of this plugin. The Android/Gradle build file is allowed to package and sign
the plugin's own application artifact; those markers are checked as build-layer responsibilities and
are prohibited from migrating into `app/src/main/java`.

The verifier checks:

- exactly 20 Kotlin production source files and every file against nine forbidden capability groups;
- the exact JAR-only input, `PROGRAM`/`CLASSPATH` roles, class-entry validation, D8 indexed-DEX output,
  and frozen protocol AAR identity;
- the exact manifest permission/action/service allowlist, with no package-install permission or action;
- build-only packaging, signing, and release markers, with no source compiler, bundletool, apksig,
  ddmlib, or AAPT runtime dependency.

Run the mutation suite:

```powershell
pwsh -NoLogo -NoProfile -File scripts/r4-other-capabilities/test-r4-other-capabilities.ps1
```

Run the real Gate:

```powershell
pwsh -NoLogo -NoProfile -File scripts/r4-other-capabilities/verify-r4-other-capabilities.ps1
```

The default report is `app/build/reports/other-capabilities/gate.json`. No compiler, package, signing,
ADB, or installation command is executed by this Gate. Any bootstrap, contract, source, manifest,
build-layer, or protocol failure atomically replaces a previous PASS with `passed=false`.
