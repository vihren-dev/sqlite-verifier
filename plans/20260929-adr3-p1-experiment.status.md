# ADR 0003 P1 comparative experiment status

Created 2026-09-29. Status: DONE.
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
- 2026-09-29: Added the data path and stage reuse. `contract.py` compiles the
  trusted stages for `verify`, `verify-bundle` and `prepare`; `stage_store.py` and
  `cache_eligibility.py` implement opt-in reuse (generated stages eligible,
  approved closures only via the empty registry or the measurement-only
  override); `inputs.py` shares SQL translation; `prepare.py` and `bundle.py`
  implement the experimental commands. Tests: `bundle_test.py` (4 examples match
  `verify`; `sorry`, forbidden axiom, wrong target, altered contract and wrong SQL
  rejected), `stage_reuse_test.py`, `test_stage_store.py`; new Nix target
  `tests.bundle` (13 passed in the sandbox). Regression: Nix targets atuin 12,
  cli 13, kernel 19, model 6; host 267; Nix infrastructure 48 (plus the 2 known
  workspace-only flake failures).
- 2026-09-29: Added the P1 harness (`p1_cases.py`, `p1_measure.py`,
  `p1_report.py`) and the manual Linux workflow `.github/workflows/adr3-p1.yml`
  (baseline default `6a6705167b4f7cf614875c6f81ceb91cdacfe6e4`, the commit before
  the P1 changes). Smoke run on the refutation example: all statuses correct.
- 2026-09-29: macOS matrix complete (234 runs, 0 wrong statuses, no regressions);
  results in `experiments/adr-0003-latency/results/Darwin-arm64.jsonl` and
  `p1-results.md`. Linux: pushed `adr3/p1-measure` (ADR 0003 and P1 commits
  duplicated onto the PR #7 head, without the unpushed ADR 0004 docs, per owner)
  with a branch push trigger; run 36553342277 in progress. Outcome open until
  Linux results arrive.
- 2026-09-29: Linux results downloaded (234 runs, 0 wrong statuses) and recorded
  in `results/Linux-x86_64.jsonl`; `p1-results.md` updated. Literal decision-rule
  outcome across both platforms: ship tuning. Owner is considering overriding the
  rule in favor of the data path; not recorded in the ADR yet.
- 2026-09-29: DONE. Owner decision recorded in ADR 0003: continue with the data
  path despite the rule's literal "ship tuning" outcome; P2 scope updated
  (supported commands, dependency-aware `prepare`, keep tuning changes, decide on
  upstreaming the exporter option, re-run the matrix).
