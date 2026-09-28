# ADR 0001 implementation status

Created: 2026-09-28. Status: IN PROGRESS.

Task: [observable requirements](20260928-pytest-nix-builds.task.md).
Specification: [accepted ADR 0001](../docs/adr-0001-pytest-and-nix-ci.md).
Baseline: `4df62fa7`, with unchanged runtime from `7a99c71f` (v0.1.1).
Relevant sources: `justfile`, `tests/`, `conformance/coverage_report.py`,
`nix/flake.nix`, `packaging/`, `tools/run_independent_suites.py`, `.github/workflows/ci.yml`.

## Progress and evidence

- Accepted the ADR and recorded the complete acceptance scope before coding.
  Existing source still uses script/unittest runners and dependency-only caching.
  Disk check: 41 GiB free; no cleanup needed. The unrelated uncommitted ADR 0002
  draft remains in the primary workspace and is excluded from implementation
  workspaces and commits. Preparation documentation links checked separately.

- Development interpreter now includes pinned pytest 9.1.1; the archive builder
  requires an explicit bare pinned Python path passed by `just runtime-package`.
  Verified that the bare interpreter cannot import pytest, archive CLI describes
  the required option, and focused resource/loader/module-deletion tests pass.
  Nix environment still has exactly two files; one persistent shell is used.
- Added the pytest catalogue, per-case runtime fixtures, bounded process runner
  and separate source/installed phase reports. Fourteen real subprocess regressions
  pass in 4.97s, covering absent tools during collection, bad metadata, setup and
  teardown errors, malformed JSON, timeout cleanup and artifact separation.
  Independent review caught and fixed installed Lean fallback to host tools;
  a regression proves missing bundled Lean fails despite an available host compiler.
  Harness checks are fresh integration evidence, excluded from pure-unit caching.
  Existing suites are being converted separately; full discovery parity is pending.
- Integrated independently reviewed Nix toolchain/parser/Lean/runtime targets and
  explicit-root packaging. Darwin Nix sandbox builds and input-identity mutation
  tests passed; real Linux execution remains pending. Nine merged staging/CI-scope
  checks pass. The Atuin run exposed read-only store modes copied into fixtures;
  `copy_mutable_tree` now makes only private copies writable, retaining executable
  bits. A regression passes both case orders and proves original bytes unchanged.

## Remaining implementation

Inventory reconciliation with actual collection; complete case conversion;
integration of reviewed Nix targets and explicit runtime packaging; CI and
cache transport; both-platform acceptance and benchmark matrix; final independent
requirement-by-requirement review. No end-to-end performance claim yet.
