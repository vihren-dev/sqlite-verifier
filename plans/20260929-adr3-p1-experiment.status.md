# ADR 0003 P1 comparative experiment status

Created 2026-09-29. Status: IN PROGRESS.
Task: [P1 experiment](20260929-adr3-p1-experiment.task.md).
Spec: [ADR 0003](../docs/adr-0003-agent-proof-preparation.md);
evidence: [latency experiments](../experiments/adr-0003-latency/README.md).
Relevant sources: `ProofChecker.lean`, `migration_check/cli.py`,
`migration_check/compile.py`, `migration_check/source_closure.py`,
`migration_check/runtime.py`, `build-support/default.nix`,
`build-support/runtime.nix`, `build-support/tests.nix`, `lakefile.toml`.

Workspace: jj workspace `adr3` at `~/work/sqlite-verifier-adr3`.

## Progress log

- 2026-09-29: Task and status created.
- 2026-09-29: Extracted shared gate checks into `GateCore.lean`; the `.olean` gate
  now imports only the trusted modules its user modules import (tuning), and
  reports positivity from submitted declarations. Added `BundleChecker.lean`
  (`migration-bundle-checker`) and a Nix-built, pinned lean4export v4.33.0 with
  the skip-trusted patch (Lake path dependency populated in the derivation;
  exporter shipped in the runtime). Existing suites pass: kernel 19, CLI/Atuin/
  compilation/baseline/model/coverage/schema 62, host 260, Nix infrastructure 47.
  Known: `test_flake_checks_reuse_existing_targets` cannot pass in this jj
  workspace because it has no `.git` (flake `./nix` needs Git to see parent
  files); it passes in a Git-backed checkout and CI.
