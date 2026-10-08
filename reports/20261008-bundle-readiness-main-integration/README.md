# Bundle readiness integration checks

Created 2026-10-08. Audience: team.
Task: [T06](../../plans/20261006-bundle-readiness.task.md).

Integration combines the existing T06 change with accepted main `d75fdc2b`.
All measurement and attack helper source hashes remain exact. Production
Lean, application, examples, conformance and CI files match accepted main.
Shared kernel fixtures invalidate both kernel and bundle targets; hostile
bundle fixtures invalidate the bundle target alone. The three original
journals remain ordered subsequences of the combined 314-row journal,
including repeated rows.

Bounded host checks pass all 137 measurement and attack-inventory tests in
6.17 seconds. Actual Nix command and dependency checks pass eight tests in
17.90 seconds, with 50 deselections. Original XML, console bytes, source
hashes and journal preservation records are retained. `manifest.json`
binds their bytes. Fresh actual macOS Nix sandboxes pass all 65 bundle tests in 325.39 seconds
and all 28 kernel tests in 48.21 seconds. Ordinary source acceptance passes
507 tests and 35 subtests in 50.32 seconds, with 100 explicit deselections.
The source XML counts the subtests separately, for 542 successful records.
No failure, error or skip occurs. The selected accepted-main runtime is
`/nix/store/dv07xmydabx71bmkw4axpy4z1dfia0ph-sqlite-verifier-runtime-1`.
Exact test outputs are
`/nix/store/bl42x5pv5nbmzcigv6x1vzp91550ip7b-sqlite-verifier-test-bundle-1`
and `/nix/store/6ylpwamwvjdibxwrwbr5kg18si2wxmgc-sqlite-verifier-test-kernel-1`.
Original XML and complete console bytes are retained.

The resource guard first refused validation below the 10 GiB minimum.
The owner then authorized removal of the single completed pytest directory
in the cleanup proposal. The exact cleanup receipt records about 11.2 GiB
free afterward, and the guard passes. The proposal and receipt remain here.
No repository, retained acceptance archive or Nix store path was removed.

Synthetic observations and test durations are not cold-run performance
evidence. The actual campaigns still wait for the accepted documentation
runtime and coordinated idle hosts. Integration review `20261008T073925Z-849bceae` has no findings. The
reviewer did not run hash commands; author checks independently verify
every artifact hash and the decompressed console log. Remaining ordinary
Nix acceptance is running. T06 remains IN PROGRESS.
