# R4.2-G0 D8/R8 boundary gate

This directory freezes the current D8 provider surface before any independent R8 provider exists.
It is a fail-closed source/artifact/documentation gate, not an R8 implementation or runtime test.

Run the mutation self-test without Gradle or Android tooling:

```powershell
pwsh -NoLogo -NoProfile -File scripts/r4-r8-boundary/test-r4-r8-boundary.ps1
```

The self-test has a fixed 22-case shape: one real positive fixture plus fail-closed identity,
manifest/service, D8 dispatch, Kotlin/Java runner, mode mapping, AAR, documentation, malformed
gate-input, stale-output, and direct/link-alias mutations.

Run the repository gate and atomically persist its machine-readable report:

```powershell
pwsh -NoLogo -NoProfile -File scripts/r4-r8-boundary/verify-r4-r8-boundary.ps1 `
  -RepositoryRoot . `
  -OutputPath app/build/reports/r8-boundary/gate.json
```

The gate pins:

- the DEX action, category, service, isolated process, permission, and discovery/runtime IDs;
- D8-only JAR to DEX ZIP capabilities, DEBUG/RELEASE modes, and `NOT_CLAIMED` determinism;
- one `toD8ExecutionMode` policy with exact mode and CLI mappings;
- the production `D8Command`, `D8.run`, and API 24/25 `D8.main` invocation surface;
- the sole remote-session construction and dispatch into `D8DexCompilerEngine`;
- absence of production `R8`/`R8Command` invocation;
- full SHA-256 pins for the manifest, runtime identity/capability source, PluginInfo, engine,
  remote session, and Android application-ID build source;
- the consumed `dex-compiler-api.aar` SHA-256;
- the root README statement that D8 RELEASE mode does not provide R8 semantics.

Every report, including a persisted failure, stays `SOURCE_STATIC_ONLY` and records
`r8ProviderImplemented=false`, `jvmVerified=false`, `binderVerified=false`,
`r8Executed=false`, and `deviceVerified=false`. A surrounding Gradle task may separately depend
on JVM tests, but this standalone static report does not ingest or bind their XML results.
Passing this gate does not prove compilation, Binder/PFD transport,
APK behavior, an independent R8 provider, or any device result.

For output safety, both the bootstrap and imported module reject direct, hard-link, and
ancestor-link aliases of pinned inputs. They also reject every output path inside
`app/src/main` or this gate directory, including paths that do not exist yet.
