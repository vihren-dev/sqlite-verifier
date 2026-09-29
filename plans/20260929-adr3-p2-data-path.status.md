# ADR 0003 P2 status

Created 2026-09-29. Status: DONE.
Task: [P2 data path](20260929-adr3-p2-data-path.task.md).
Spec: [ADR 0003](../docs/adr-0003-agent-proof-preparation.md);
evidence: [P1 results](../experiments/adr-0003-latency/p1-results.md).
Relevant sources: `migration_check/prepare.py`, `migration_check/source_closure.py`,
`migration_check/bundle.py`, `migration_check/cli.py`, `BundleChecker.lean`,
`build-support/lean4export.nix`, `tests/bundle_test.py`,
`tests/runtime_package_test.py`.

Workspace: jj workspace `adr3` at `~/work/sqlite-verifier-adr3`, on top of
PR #11 (`adr3/data-path`).

## Progress log

- 2026-09-29: Task and status created. Atuin's `AtuinWitness` and
  `HistoryDecodingChecks` do not import `SqlInputs`; P1's chained keys recompiled
  them on every SQL edit.
- 2026-09-29: Dependency-aware `prepare`: `discover_sources` can report each
  module's full import list; `module_keys.py` keys each candidate module by its
  source, the runtime identity and its imports' keys (approved modules and
  `SchemaInputs` share a contract key, `SqlInputs` has its own). An Atuin SQL edit
  now reuses `AtuinWitness` and `HistoryDecodingChecks`. Tests: 5 key unit tests,
  a bundle case preparing twice around a SQL edit. Nix: atuin 12, bundle 15,
  cli 13, model 6; host 280.
- 2026-09-29: `prepare` and `verify-bundle` are supported commands: help text no
  longer says experimental; `docs/data-path.md` documents usage, JSON reports,
  exit codes, bundle format v1 and the pinned-exporter decision (keep the patch;
  upstreaming is a separate owner-approved step) with its upgrade procedure; the
  README links it. Installed acceptance adds prepared positive, refuted and
  wrong-SQL cases: `just runtime-package` 21 passed on aarch64-darwin.
- 2026-09-29: Re-ran the matrix on both platforms (macOS local at `ad1c901d`;
  Linux run 36570573314 on temporary branch `adr3/p2-measure`): 468 runs, all
  with expected statuses. Atuin SQL edits now 27–38% faster than tuning (P1:
  2–5%); refutation SQL edits still 28–36% slower (explained in
  `p2-results.md`); no data-path regression beyond noise. Results in
  `experiments/adr-0003-latency/p2-results.md` and `results/p2/`; ADR P2 row
  links them. DONE, except Linux installed acceptance, which PR CI covers.
- 2026-09-29: PR #11 CI run 36574100133 (package scope) passed on both platforms,
  including Linux installed acceptance (21 passed) and all 50 Nix infrastructure
  tests. P2 fully DONE.
