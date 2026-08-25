# R4 D8 default-pin promotion and rollback gate

This local-only gate closes the distinction between a candidate override and an actual default-pin
promotion. It requires three fresh 60-cell producer invocations under one normalized source/build
identity:

1. `PROMOTED_DEFAULT`: catalog pin `8.13.22`, no override, Gate `PINNED_DEFAULT`.
2. `OLD_PIN_ROLLBACK`: catalog pin `8.13.17`, explicit `d8RollbackEvaluation=true`, Gate
   `OLD_PIN_ROLLBACK`.
3. `FINAL_PROMOTED_DEFAULT`: catalog pin restored to `8.13.22`, no override, a new
   `PINNED_DEFAULT` producer UUID and report set.

The rollback property never selects a dependency version. It only tells the verifier to require that
the catalog itself contains the byte-pinned old version. The source identity includes every tracked
and non-ignored file and permits raw-byte differences only in `gradle/libs.versions.toml`; that file
is normalized at the exact `r8 = "..."` assignment before the three identities are compared.

Each state also binds the exact Maven Local `platform-versions` 1.4.1 JAR, its clean sibling source
commit, the Android runtime-library fingerprint, the D8 Gate/report-set hashes, and a unique producer
UUID. The final Gate remains `determinismClaim=NOT_CLAIMED` and performs no device or remote action.

The state capture and final verifier invalidate their output before consuming evidence and replace a
stale PASS atomically on failure.
