# Proof exporter owner review

Status: APPROVED on 2026-10-07. Created 2026-10-06.

Task: [proof exporter driver](20261006-proof-exporter-driver.task.md).
Review rule: [R8](../docs/review-checklist.md), “owner review required” for
changes to the export path. The owner approved PR #47 at unchanged reviewed
head `07dc71b323808ac03991407e75dd4e74031924cb` in the implementation chat
on 2026-10-07. This records acceptance of the omission logic, merged import
view and installed producer described below.

## Change to inspect

`ProofExporter.lean` uses upstream lean4export v4.34.0 without a patch.
`prepare` passes the protected `SqliteVerifier` base and the same trusted
imports that appear in its version-1 bundle header. The driver follows
actual direct/transitive imports and declaration-origin module indices.
Only declarations supplied by that closure are marked visited before
upstream metadata and declaration emission.

The proof roots, generated/approved comparison records, bundle format,
kernel gates, axiom policy and verification target retain their meanings.
Upstream handling of unsafe and partial declarations is unchanged.
`migration-proof-exporter` replaces the patched upstream executable in the
installed runtime. No patch or patched producer derivation remains.

Lean selects package directories before modules. The shared compiler and
exporter import view merges split package directories while preserving each
original root's file precedence. Canonical installed trusted files remain
ahead of a candidate collision. The kernel checker's trusted roots remain
the original sysroot and installed library. The mechanism has no package
name or namespace-prefix omission rule and supports separate package roots.

## Evidence

The immutable T03 baseline receipts on both supported platforms bind the
same small, refutation and Atuin inputs and bundle digests. Darwin's new
producer passed all three byte/hash/status comparisons. A used declaration
from caller module `SqliteVerifier.Candidate` prepares and verifies through
the public commands. The isolated bundle target passed its 41 cases,
including attack checks and generated-input parity, with no skips.

Additional actual Lean tests passed: a conflicting candidate module cannot
replace a trusted definition during split-package compilation; the exporter
omits transitive trusted declarations in an unrelated namespace and exports
a caller declaration in a trusted-looking namespace.

`just test` passed with 353 source checks and all six development Nix suites:
Atuin 12, bundle 42, CLI 13, kernel 19, sample 12 and upstream 58. Nix source,
isolated-target and offline-staging checks passed all 72 cases.

The actual offline-installed Darwin archive passed 30 cases, including all
three exact baselines, the caller module in the library namespace, Atuin and
the original installed data path. The installed fixtures poisoned ambient
Python and Lean import paths.

Claude review of `79e844a5` reported two R8 owner-review requirements and one
R9 docstring recommendation, with no correctness defect. The docstring was
clarified. Both R8 findings were resolved after the owner's explicit approval
on 2026-10-07; the approval record `79fe3504` passed independent review.

Correction `5a18b5bf` passed Claude review with no findings and identical
runtime executable digests. Native Linux validation passed all development
suites, 68 Nix checks, 21 original installed cases and all nine new installed
exporter cases. The [execution packet](../reports/20261006-proof-exporter-driver/README.md)
retains both platforms' receipts and original JUnit bytes, plus the Linux
source inventory and exact executed helper. All 823 Linux source files remain
bound to the transferred reviewed revision.

Execution packet `35b6dbee` passed Claude review with no findings
(`20261006T150137Z-35b6dbee`). The technical work and independent reviews are
complete. The owner approval above is recorded, and the approved Lean upgrade
was merged through PR #43 as `bc9e2dce`. Publication integration preserves all
101 exporter/import-view/pin/baseline and receipt files checked against the
approved head. Main updates two engine-settings caller files, so the combined
runtime has a new identity. The separate
[current-input receipt](../reports/20261007-proof-exporter-integration/summary.json)
records a fresh Darwin assembly and all three fixed T03 bundle-byte/status
comparisons, plus origin and collision tests. Historical both-platform receipt
bytes are unchanged. Normal PR checks and delivery remain pending; release is
a separate decision.
