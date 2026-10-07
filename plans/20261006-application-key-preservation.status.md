# Application-key preservation status

Status: IN PROGRESS. Created 2026-10-06.
Task: [application-key preservation](20261006-application-key-preservation.task.md).
Source: [issue #16](https://github.com/vihren-dev/sqlite-verifier/issues/16).

## Current publication boundary

This is the existing T15 task. Its helpers use declared logical keys and complete
record permutations over the flexible interpretation and contract primitives.
The feature formulas and example policy remain the reviewed implementation.

The clean publication base is the approved T05 implementation at
`8e10a593bf830c272bf6b5e6af525d943ce90212`. Owner approval of T05 is recorded
in [PR48](https://github.com/vihren-dev/sqlite-verifier/pull/48); hosted integration
and repository delivery remain pending. T15 has no additional owner design
question. A PR waits for dependency delivery or explicit stacked publication.
This task is not DONE and does not authorize a verification-path cutover.

## Preserved mixed-history evidence

The original working copy is retained by local bookmark
`t15-mixed-history-acceptance` at `fbd214a1`. Its checked source is
`26b6773e9f794bd58c52505f6cb557beee26922d`, and its local acceptance checkpoint is
`ec78936e788d1d787cc4d2cfa0c8ea2af883c7e5`. The prior full status and every raw
review row remain in that history. Its snapshot and receipt hashes are retained
in `build/t15-publication-source-20261007/manifest.json`.

Those checks used a maintenance tree that included held T18b tooling. They are
valid evidence for that tree, not current acceptance of the clean change:

- Compiler/domain and preservation proofs passed with explicit 15- and
  30-second bounds. All helper and example corrections passed independent
  Claude reviews. Review `20261007T064647Z-26b6773e` has no findings.
- Three real packaged-example nodes passed in 31.43 seconds: direct CLI,
  bundle parity and independent preparation repeatability. Receipt:
  `build/t15-packaged-example-receipt.json`. The bundle was 9,390 bytes with
  SHA-256 `a2e63cc3a638a5dca3159d252b5cb3b8afbaddc27ff51fde31da1ed72563fdb4`.
- Ordinary `just test` passed 370 tests and 28 subtests (398 XML entries),
  six Nix suites with 187 checks, and a 281/281 documentation inventory.
  Receipt: `build/t15-local-ordinary-receipt.json`. The full model was excluded.
- A fresh Darwin archive passed all 27 standard package, Atuin and exact T15
  installed nodes in 182.52 seconds. Receipt:
  `build/t15-local-installed-receipt.json`; XML:
  `build/test-results/t15-local-installed.xml`. Archive size: 1,113,676,158 bytes;
  SHA-256 `cb91d5e0585e8366eb3f356a78ca76c107e8222a23b1e90a762a550d35e2691a`.
  It used `--runtime-variant installed --runtime-archive` without runtime-root.
- The original archive, checksum, source XML, installed XML, direct receipts,
  logs and runtime identities remain untouched under `build/`. They establish
  no performance result or acceptance of a later integrated runtime.

## Clean integration scope

The publication change contains three ApplicationKey modules; three new public
entry imports; seven `examples/application_keys` files; the example-index and
baseline-scope guidance; the domain/proof test; the CLI case and bundle parity
and repeatability tests; this task/status; and preserved review evidence.
The held general public walkthrough and T18b Nix, workflow, inventory, reference
and dependency packaging are excluded. No T07 model change is included.

The approved base supplies the current executor, contract, gates, source-schema
binding, protected baselines, mutation-source correction, model-only 600-second
bound and retained acceptance evidence. Those files stay unchanged. Source
copying does not turn old mixed-history receipts into clean-runtime acceptance.

## Progress

- 2026-10-07: Audited the mixed tip before mutation. Its raw diff from the
  approved base had 97 files, including held documentation tooling and deletion
  or reversion of accepted ADR, timeout and mutation evidence. Eleven selected
  model, contract and gate files were byte-identical to the approved base.
- Recorded the exact T15-only path and hunk inventory. The three public imports
  are retained without copying the 69-line general walkthrough. The two existing
  test-file diffs contain only the T15 case and repeatability support.
- The coordinator authorized a clean change over the approved base. Saved the
  original working copy under its local bookmark before changing the workspace.
  Saved 17 selected source/journal files and seven original receipt identities.
  Established the clean base and updated this task/status before copying code.

## Remaining acceptance

The clean source unit needs bounded compiler, source and example checks and
independent review. Fresh runtime assembly, ordinary integration and installed
acceptance require coordinated native leases; no full model or installed
campaign runs before the clean unit is reviewed. The three installed T15 nodes
need explicit selection because the standard package/Atuin selection omits
them. Earlier receipts and cached artifacts do not substitute for those checks.

The task specifies no additional native platform gate beyond its relevant
source, example, ordinary and installed checks. Hosted publication still follows
the repository's native CI checks. Dependency delivery, a reviewable clean
feature diff, required hosted checks and T15 delivery remain pending. Every
command retains an explicit timeout. No PR, main write or publication has run.
