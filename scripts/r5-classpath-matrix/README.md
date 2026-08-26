# R5.3 V1.1 classpath device matrix

`run-r5-classpath-cell.ps1` records one explicitly authorized device cell. It never enumerates
devices, starts or stops an emulator, invokes Gradle, or sends ADB commands without the exact
`-s <serial>` supplied by the caller. A formal cell requires clean host/plugin repositories,
same-signer v2 APKs, four scoped packages absent before the run, the exact focused instrumentation
selector to report `OK (1 test)`, and all four packages absent again after cleanup.

`verify-r5-classpath-matrix.ps1` consumes exactly three cell reports and fails closed unless they
share one campaign and one host/plugin/APK identity, include an API 24/25 emulator, an API 26+
emulator, and an arm64 physical device, and retain valid self-excluding SHA-256 manifests. The
result is representative R5.3 coverage, not a new seven-cell canonical R1 gate.

Example cell invocation:

```powershell
.\scripts\r5-classpath-matrix\run-r5-classpath-cell.ps1 `
    -CampaignId '<campaign-uuid>' `
    -MatrixCellId 'api24-x86-avd-api24' `
    -Serial 'emulator-5558' `
    -DeviceKind EMULATOR `
    -ExpectedApi 24 `
    -ExpectedAbi x86 `
    -ExpectedAvdName 'AVD_API_24'
```

The caller owns emulator lifecycle and must use `-no-snapshot-save` for a run-created AVD.
