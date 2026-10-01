# ADR 0003 P3 status

Created 2026-09-30. Status: DONE.
Task: [P3 generated inputs](20260930-adr3-p3-generated-inputs.task.md).
Spec: [ADR 0003](../docs/adr-0003-agent-proof-preparation.md),
[conformance format v1](../docs/conformance-format-v1.md).
Relevant sources: `BundleChecker.lean`, `GateCore.lean`,
`VerifierConformance/Json.lean`, `conformance/case_format.py`,
`migration_check/bundle.py`, `migration_check/contract.py`,
`migration_check/inputs.py`, `migration_check/sql_model.py`.

## Progress log

- 2026-09-30: Integrated `adr3/data-path` onto `adr4/model-conformance` (PR #11
  retargeted onto PR #12's branch): dropped four commits already contained there,
  merged `lakefile.toml`, `build-support/default.nix` (shared `lakeDependencies`,
  also for the coverage build), `justfile`, `tests/test_nix_test_targets.py` and
  `build-support/README.md`. Nix targets atuin 12, bundle 15, cli 13, model 56,
  kernel 19; host 284; Nix infrastructure 58 (in the updated dev shell).
- 2026-09-30: Task and status created. Lean 4.33 supports `deriving ToExpr`.
- 2026-09-30: DONE. `StructuralCodec.lean` holds the shared JSON codecs and derived
  `ToExpr` instances (the conformance library imports it; `SqliteVerifier` still
  does not import `Lean`). `migration_check/structural.py` holds the encoders,
  re-exported by `conformance/case_format.py`. `BundleChecker` takes the frontend's
  record, checks its starting schema against the compiled one, constructs
  `Generated.nextSchema`/`script`/`profile` through the kernel, and compares
  exported copies of those three by definitional equality; `--parity` compares the
  construction with compiled `SqlInputs`. `verify-bundle` no longer compiles
  `SqlInputs.lean`.
  Parity testing found one difference: conformance cases order indexes by name,
  the emitter keeps declaration order; generated inputs now use declaration order.
  Tests: `tests/generated_inputs_test.py` (13 parity, 5 tampering). Nix: atuin 12,
  bundle 33, cli 13, model 56, kernel 19; host 284; Nix infrastructure 59.
  Measured on macOS, no stage store: `verify-bundle` 2.62 s → 2.15 s (small),
  6.69 s → 6.29 s (Atuin). Installed acceptance is left to PR CI.
- 2026-10-01: ADR 0003 closed (owner agreed): ADR 0003 status updated to
  implemented and closed, ADR 0002 marked superseded. Kept, as recorded in the ADR
  status: measurement workflow, measurement-only override and the
  `adr3/p1-measure`/`adr3/p2-measure` branches. Trust milestone deferred. PR #11
  rebased onto `main` after PR #12 merged.
