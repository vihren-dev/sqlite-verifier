# Trusted execution status

Created 2026-09-29. Status: DONE.
Task: [trusted execution](20260929-trusted-execution.task.md).

User authorized removing source execution isolation now and deferring integration
isolation until after ADR-003. Prior uncommitted Atuin recipe split is superseded
by a cached Atuin target included in `just test`.

Implementation and validation complete. Existing unrelated draft ADR-002 and
component research remain outside this change. ADR-003's isolation scope will be
updated to reflect the explicitly authorized decision.

Implemented: plain bounded process execution replaces OS policy; runtime manifests,
bubblewrap dependency/probe and isolation tests removed. Atuin is a declared Nix
pytest target included in `just test` and selectable via `just test-atuin`.

Validation so far (aarch64-darwin):
- Focused process/CI/cache regressions: 23 passed.
- Nix targets: Atuin 16, kernel 19, model 6 passed with sandbox=true/fallback=false.
- Atuin warm reuse: same output, no pytest execution, 5.44s wall time under concurrent tests.
- Offline runtime archive rebuilt and verified; installed acceptance: 19 passed.
- Linux Atuin derivation evaluates; native Linux execution remains CI work.
- Changed/tracked Markdown links resolve. Two unrelated pre-existing drafts have
  13 broken links; the repository-wide documentation checks still report these.
- ADR-003 updated in place with the owner’s trusted-execution scope decision;
  all three pre-existing draft documents remain outside the implementation commit.

Full source recipe completed: 283 host cases and 136 subtests passed; it reported
one obsolete embedded filesystem-containment probe and the pre-existing draft-link
failure. Removed both embedded I/O probes from the compilation fixture, preserving
source/generated-input/artifact/kernel assertions; all 17 compilation cases passed
on rerun. Across final selections, 325 source cases pass (284 host + 41 Nix), with
only the unrelated documentation-link case outstanding. No blanket full rerun was
needed after this fixture-only correction. All 332 collected identities and
implementation hashes reconcile with the inventory. `just test-atuin` was also
verified against the warm output.

The implementation commit excludes the three pre-existing draft documents,
including the updated ADR-003 draft. Its scope note remains in the working copy.
No Lean model or checker logic changed. Process/output limits and logical approval
checks remain; hostile tactic execution is explicitly outside the current scope.
