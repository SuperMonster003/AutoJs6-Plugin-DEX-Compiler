# R5.3 clean-directory determinism investigation

This gate compares two independent, clean worktrees at one exact commit after both have run:

```powershell
.\gradlew.bat :app:verifyR4D8UpgradeMatrix --rerun-tasks --offline --no-daemon --console=plain
```

Pass the two persisted R4 Gate files and their producer-specific 60-cell report directories to
`compare-r5-clean-directories.ps1`. The comparator revalidates each pinned-default R4 Gate against
the matrix and report schema checked out in that same worktree (including its filesystem byte
representation), requires the same clean commit/matrix/schema/compiler and cell set, then records input, runtime,
compiler-outcome, output-status, DEX topology, output-digest and per-DEX byte-manifest differences.

Even when all output digests match, the output remains bounded to one machine and two clean
directories and always writes `determinismClaim = NOT_CLAIMED`. It is an investigation receipt,
not a general claim across machines, filesystems, JDKs or future compiler versions.
