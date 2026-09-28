# Real source identity checks — 2026-09-28

Task: [pytest/Nix builds](20260928-pytest-nix-builds.task.md), ADR0001 B1/T4.
Base: lead checkpoint `d7ca0c2b`. Author: inventory/conformance member;
reviewers: formal_preservation and root. Scope: real Nix fileset checks, their
normal source-suite routing, narrowly corrected Git prerequisite and inventory.

DONE: the hidden `build-support/source_identity_test.py` runner is replaced by
42 collected pytest cases. Thirteen selected input relations each verify exact
component changes for add/edit/rename/delete; fifteen mandatory input relations
verify exact edit effects and fail-closed delete/rename; nine component roots
exercise every generated-directory category; five unrelated/excluded files prove
identity invariance. All current parser extensions, unit Python/input files,
runtime inputs and root/nested Lean inputs are represented. Multiple mutations
of the same input relation intentionally share one case, keeping the matrix
proportional while retaining every membership assertion.

Fixtures create only tiny synthetic declared files. A session baseline supplies
real locked-Nix source identities, and each selected case receives a private copy.
No checkout/parser source archive/build outputs are copied; evaluations are offline
and never build packages. Each Nix command has a 30-second deadline. The ordinary
source orchestrator discovers these cases on both native platforms with an explicit
150-second group deadline, matching environment snapshots and leaving existing
limits untouched. The README documents the selectable pytest command; the obsolete
script wrapper is removed. Only the environment snapshot's git_parent parameter
now requires the native Git prerequisite.

Validation: 42 identity cases plus both environment snapshots pass in 29.86s on
native Darwin. A selected parser membership case also passes alone in 1.45s.
Actual collection verifies all 44 identities and the parameter-specific Git marker.
An initial fixture expression used Nix's string-like builtins.toPath result where
filesets require a path; using the original path-addition form corrected this code
error before the passing run. No environment workaround or production build occurs.

Inventory now adds 42 explicitly new B1 mappings (397 total on this branch), while
preserving all 244 original legacy mappings and the immutable baseline hashes.
The reviewed unit manifest is unchanged. Overall ADR acceptance and Linux execution
remain lead-owned integration work, not a claim of this bounded contribution.

Independent static review by formal_preservation approved all 42 input relations,
private fixture copies, unaffected-component equality, mandatory-name failures
and both timeout bounds. Final structural checks confirm 397 unique inventory
rows and exact collected metadata for the 42 additions and Git-only prerequisite.
