# Step 1 source compilation

Created: 2026-09-24. Status: DONE for this compiler component; Step 1 remains IN PROGRESS.
Task: [Step 1](20260924-step-1-schema-extensions.task.md).
Specs: engineering brief, roadmap and team guide at repository root.
Owner: integration engineer. Reviewers: coordinator, conformance reviewer, technical lead.

## Delivered

`migration_check/compile.py` and `migration_check/source_closure.py` implement
source-only dependency snapshots, isolated approved/data/candidate compilation,
exact source hashes, bounded compiler diagnostics, and validated artifact copying.
The public interface and trust boundaries are documented in
[Source staging](../docs/source-staging.md). The parent owns CLI orchestration,
sandbox platform integration, shared check recipes, and hosted CI execution.

## Evidence and review

- `nix develop --command timeout 180 python3 -m tests.compilation_test` passed
  with real Lean 4.33.0, full formal library, macOS sandbox and kernel gate.
- Independent conformance review reproduced the complete suite under a 60-second
  outer timeout using final sources, including removal of broad store access,
  and accepted the component. Coordinator source review also accepted it.
- Review found and fixed case aliases/hardlinks bypassing selected-source
  exclusions, and artifact parent-directory symlinks escaping compiler scratch.
  Regression tests cover these boundaries; all expected companions are validated
  before any copy. Candidate inputs cannot enter approved compilation through
  the candidate-only root paths or broad `/nix/store` visibility.
- The technical lead separately accepted kernel-gate commit `f664abda` after
  independent review and full reproduction against formal library `1f0c28bf`:
  honest proof accepted, initializer ignored, eight attacks rejected.
- Final reviewed source snapshot `19d50fa1` was restored byte-for-byte after a
  concurrent jj ancestor update selected an older divergent snapshot. The three
  implementation/test files have no differences from the successfully tested
  snapshot. No additional code change was made after the final test.

Linux runtime/library alias behavior remains a hosted CI check; the coordinator
owns its sandbox fix. This unit does not claim a complete CLI, product release,
or successful remote CI execution.
