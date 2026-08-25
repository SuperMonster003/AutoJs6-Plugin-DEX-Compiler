# R4 R8 cross-repository closeout Gate

This Gate closes the DEX Roadmap's aggregate R8 requirement without changing the historical scope
of the R8 G2-G8 reports. It is intentionally read-only.

It verifies all of the following in one fail-closed invocation:

- the exact G2-G8 report bytes, invocation IDs, schemas, evidence boundaries, prerequisite chain,
  device totals, ART/JNI/Retrace claims, and Private-publication claims;
- the clean, privacy-normalized R8 repository at the pinned `origin/master`, including its annotated
  prerelease tag and exact `local.5` assets;
- the AutoJs6 R8 integration commit as an ancestor of the current host, with all 57 evidence-bound
  host files unchanged and clean and the frozen R8 API AAR byte-identical;
- live GitHub repository, branch, tag, prerelease, and asset-digest metadata through read-only
  `gh api` requests; the repository must remain Private and `publicPublished` must remain false.

The verifier does not fetch or push Git refs, change repository visibility, create or edit a
release, download release assets, read signing material, invoke ADB, or run a device task.

Run the mutation regression suite:

```powershell
pwsh -NoLogo -NoProfile -File scripts/r4-r8-closeout/test-r4-r8-closeout.ps1
```

Run the real closeout:

```powershell
pwsh -NoLogo -NoProfile -File scripts/r4-r8-closeout/verify-r4-r8-closeout.ps1
```

The default output is `app/build/reports/r8-closeout/gate.json`. A fresh invocation ID is emitted
on every run. Any bootstrap, contract, module, local evidence, Git, host, authentication, or live
GitHub failure atomically replaces a previous positive report with `passed=false`.
