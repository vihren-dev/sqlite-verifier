# Stable prediction inputs after Python runs

Created 2026-10-24. Status: DONE. Required outcomes and checks passed.
Status: [status file](20261024-prediction-source-filter.status.md).
Specs: ADR 0011 judge/subject separation and ADR 0020 local build loop.
Base: the completed text-build-boundary change, when its PR is ready.

## Present problem

During the text-build-boundary task, `test-full` created two `.pyc` files below
`belay/sqlite/__pycache__`. The next verdict rebuilt all predictions because
`integrity/judge.nix` includes the whole `belay` directory in `subjectSources`.
The Lean runtime and Python sources were unchanged. The exact derivations and
source differences are recorded in this task's status file.

## Required outcomes

- Running Python and adding, changing or removing its bytecode cache below
  `belay` does not change the prediction derivation's identity.
- Changing an actual Python source below `belay` or `conformance` still changes
  that identity. The runtime still receives every source it currently imports.
- The frozen predictions remain byte-identical. The judge's identity, locked
  parts, claims and native oracle remain unchanged. This is a subject-input
  filter correction, not a change to SQL behavior or the verdict rules.
- Use the smallest source-selection change that fixes this observed cost. Keep
  the existing build graph and test helpers; no new cache or source framework.

## Tests and acceptance

Use the actual `integrity/judge.nix` expression to compare prediction derivation
identities before and after bytecode changes, and before and after a real source
change. The existing fixture in `tests/test_judge_lock.py` copies only the lock's
inputs; it cannot evaluate predictions by itself. An identity fixture needs
minimal `belay` and `conformance` Python sources and a fixed stub of
`build-support/default.nix` that supplies the subject runtime. It evaluates the
actual judge expression, not a copy of the filter. Do not copy the full checkout
or build predictions for each identity assertion. Include finite timeouts and the existing
`requires_nix` suite selection. Keep the lock's existing tamper checks passing.

Compare one before/after frozen-prediction output over all corpora, and require
the existing claimed verdict. One coherent implementation commit gets targeted
checks and independent review. At task end run `just test-full`, `just verdict`,
`just test-nix` and `just test-scheduled-checks` at their usual cadence. Cached
Nix results may be reused when their inputs match. The owner override is in
[the build-boundary status](20261024-text-build-boundaries.status.md).
Only Nix results are acceptance evidence in status files and PRs.

`integrity/judge.nix` is protected by CODEOWNERS. Keep this task in its own PR
for that review. Verify the computed lock values are unchanged; do not invent
a lock change when no locked part changes. No package source edits are planned.

## Existing code

`subjectSources` in `integrity/judge.nix` uses an unfiltered `../belay` and an
existing Python-file filter for `../conformance`. The current `belay` tree
contains Python modules only. `tests/test_judge_lock.py` already evaluates a
small copied judge expression and tests exclusion of the judge's own bytecode.
`tests/test_source_identity.py` checks package source boundaries but does not
cover this prediction-only source tree. No unrelated identity suite expansion
is needed.
