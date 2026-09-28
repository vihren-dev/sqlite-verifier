# Selection isolation evidence — 2026-09-28

Task: [pytest/Nix builds](20260928-pytest-nix-builds.task.md), ADR0001 T4.
Author: inventory/conformance member. Base: reviewed integration `092412ca`.
Scope: actual individual selections; the lead owns the final full-source reversed
run and installed-runtime ordering. Overall acceptance remains pending.

The integrated inventory contains 401 unique IDs: 395 source, 19 installed,
with 13 shared Atuin IDs. Every one of the 244 frozen legacy mappings remains.
The inventory refresh and the four independently reviewed descendant-cleanup
additions are already part of the base commit.

A source-only receipt audit requires exactly one selected ID, exit zero and passed
setup/call/teardown phases. It scans retained build reports in the four team
workspaces and never treats an installed receipt as source evidence. The audit
finds the prior CLI19, Atuin13, kernel19, compilation17, early-baseline7 and timeout4
individual checks plus other previous selected checks.

A new sequential batch ran 139 previously unverified resource-free cases, each
in a separate pytest process, in the existing pinned Nix development environment.
Every selection passed. Each command has a 90-second outer deadline, shares run ID
`isolation-6e018bf3-3588-47d2-b67b-4c7ebe4b6aad`, and explicitly selects immutable
runtime `/nix/store/00b6q3j0lwsh55597prmyv63awq5bsff-sqlite-verifier-runtime-1`.
No parser, Lean or Nix derivation build was performed.

Artifacts in this workspace:

- `build/isolation-resourcefree-results.json`: exact 139 IDs and exit codes.
- `build/test-results/source/isolation-resourcefree-*.json`: independent phase reports.
- `build/isolation-resourcefree-*.log`: complete individual pytest output.
- `build/selection-isolation-audit.json`: all 395 source IDs with matching receipts.

After this batch, 225 of 395 source cases have observed passing standalone
reports. The remaining 170 require declared resources. The lead will run the
two native-reuse cases against its already-built source checkout; this member
will run the other 168 after the lead releases the shared heavy test window.
The pending set includes 76 parser cases and 41 source-identity relations.
These counts describe actual evidence, not an inference from fixture structure.


## Final native selection reconciliation — DONE (bounded audit)

Final integration base: `ffc49c06`. The eight reviewed Linux packaging cases
bring the inventory to 409 unique IDs: 403 source and 19 installed, sharing the
13 Atuin IDs. No frozen legacy mapping was removed. The lead refreshed current
implementation metadata in that integration commit.

All 168 remaining resource-dependent selections passed separately on native
Darwin, after the lead released the shared heavy window. They use the same
explicit immutable runtime as the first batch, a 180-second outer bound per
selection, and run ID `isolation-da095eba-a89f-4c8e-8dbb-6def2b506da9`.
The source case bodies ran at the reviewed `092412ca` checkpoint; the final
packaging additions and wrapper cleanup do not alter those selected bodies.
The lead independently ran both source native-reuse cases in its existing built
checkout and all eight newly added packaging cases individually and reversed.
No implicit build or competing Lean execution was introduced by this audit.

Final exact-set reconciliation of successful retained phase reports establishes:

| Runtime | Expected IDs | Passed alone | Passed in reversed selection |
| --- | ---: | ---: | ---: |
| Source | 403 | 403 | 403 |
| Installed | 19 | 19 | 19 |

Every accepted receipt has exit zero and passed setup, call and teardown phases.
Standalone receipts contain exactly one node. Reverse evidence comes from the
lead's full 395-case reverse run (327.20s, 166 subtests, fresh passing coverage),
its eight-case packaging reverse run, and its separate installed Atuin13 and
runtime-package6 reverse runs. There are no pending IDs in either runtime.

Final artifacts in this workspace are `build/isolation-resource-results.json`,
`build/test-results/source/isolation-resource-*.json` and the per-case logs;
`build/final-selection-isolation-audit.json` maps every final runtime/node pair
to its standalone and reverse report paths across the team workspaces. The lead's
remaining receipts are under `build/final-selections`, `build/final-source-order`
and `build/installed-order-checks` in its workspace. Reports are retained separately
from ordinary source-suite evidence and cached-unit derivation evidence.

This completes local selection/isolation validation only. Remote native Linux CI,
benchmark acceptance and overall ADR rollout remain lead-owned acceptance work.

## Final failure-report integration audit — DONE (read-only)

Reviewed stable integration `12e1aebd` without changing its inventory or source.
The final catalogue contains exactly 422 unique IDs: 416 source and 19 installed,
with 13 shared Atuin IDs. The inventory and actual strict catalogue have equal ID
sets, matching descriptions, parameter IDs, levels, concern/resource markers and
all 422 current AST function locations. All 67 recorded implementation hashes
match files at the integrated revision. The new timeout parameters and existing
independent-suite timeout case explicitly retain the `/bin/ps` prerequisite.

All 244 legacy mappings retain their original source locations, labels, assertions,
legacy variants and documented semantic migration notes compared with the previous
reviewed inventory. All 39 immutable source hashes match actual bytes read from
baseline commit `4df62fa71ec64d0eb4b7aa4643a0912ab60e18a9`. The recorded catalogue
hash matches `build/integrated-422-catalogue.json`. No discrepancy was found.

The thirteen new failure-report/checkpoint cases were independently reviewed and
passed individually and in reverse order. Combining their actual phase receipts
with the prior 403 source selections yields exact standalone and reversed evidence
for **416/416 source IDs** and **19/19 installed IDs**. Every matched report has
exit zero and passed setup/call/teardown phases; standalone reports select one ID.
No runtime variant is substituted for the other.

Final audit artifacts in this workspace:

- `build/final-inventory-audit.json`: exact-set, metadata, AST and hash results.
- `build/final-selection-isolation-audit.json`: each runtime/node pair and its
  matching standalone/reversed report paths, including the thirteen new cases.

This audit performed no test execution, build or inventory edit. It confirms the
retained local evidence and final metadata; remote CI and benchmark acceptance
remain separate lead-owned decisions.
