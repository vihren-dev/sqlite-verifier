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
question. Draft PR53 is stacked while dependency delivery remains pending.
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
- The clean-base planning checkpoint passed its path, receipt and journal checks
  and was committed as `a97e1303`. Copied the 14 reviewed T15 source, example
  and test files without changing their bytes. The public entry changes only
  three imports. The diff from the approved base has exactly the 18 inventoried
  paths and no held documentation tooling or deleted accepted evidence.
- Preserved the approved base's 147 raw review rows and the mixed tree's 131
  rows as 183 rows, retaining both complete parent orders. Receipt:
  `build/t15-publication-source-20261007/journal-merge.json`. The original
  bookmark, prior source snapshot and seven checked receipt identities remain
  unchanged. Every approved-base file outside the T15 paths remains unchanged.
- Compiled all three helper/certificate modules and the clean public entry with
  the actual pinned compiler, each with a 30-second bound. Each returned zero.
  Dependency sources match the approved base in the retained immutable runtime;
  a private overlay contains the freshly compiled T15 modules. This is scoped
  source evidence, not a new Nix assembly or installed runtime. Commands, logs
  and source identities: `build/t15-clean-source-validation/`.
- The real kernel/domain test passes (one test). The three exact source/example
  nodes pass in 27.77 seconds: direct verification, bundle parity and independent
  preparation repeatability. Original XML: `key-domain.xml` and `examples.xml`
  in that directory. The outer example bound is 420 seconds; direct, preparation
  and bundle commands retain 90-, 180- and 120-second bounds. All reviewed source
  hashes and prior receipt hashes still match. No performance claim is made.
- The coordinator held fresh Nix assembly, ordinary and installed gates while
  auditing new hosted bundle-suite timeout failures on PR47/48. Those failures
  remain failures. No suite guard changed, and no heavy job ran during that
  hold. The clean source unit proceeded to its required independent review.
- The first review invocation returned exit 3 because the CLI reported no
  login. Raw row `20261007T083543Z-d2d33a6b` remains preserved. The coordinator's
  one authorized retry reviewed exact source commit
  `d2d33a6bc4e889baa90d19eaf453498720947790` and returned zero with no findings:
  `20261007T083946Z-d2d33a6b`. No new authentication or wrapper was required.
- The coordinator cleared the Darwin native lease after T02's isolated bundle
  reproduction passed under its unchanged 420-second guard. Fresh clean runtime,
  ordinary and archive-installed T15 validation now resumes. The Linux lease
  remains reserved elsewhere. No full model or performance campaign is selected.
- The first clean ordinary invocation stopped at the configured resource check,
  before building: 9.40 GiB was free against the 10 GiB requirement. Its exit 1,
  log and exact command remain in `build/t15-clean-acceptance-darwin/ordinary*`.
  No guard was lowered and no artifact was deleted by this task.
- The owner approved only the seven pytest temporary subtrees listed in
  `cleanup-proposal.json`. Coordinator cleanup session 59774 returned zero;
  `cleanup-completion.json` records 9,582,145,536 observed reclaimed bytes and
  32,653,336,576 free bytes. Source/history, archives, receipts and Nix store
  were excluded from that cleanup. The resource check then passed.
- Rechecked all seven prior receipt hashes and 439 clean code/test/example
  inputs. The earlier unknown frozen job is gone; active local work is the
  identified ci-split infrastructure suite. No process was signaled. The
  coordinator approved resuming in the configured pinned shell, with concurrent
  infrastructure as a load qualification and no performance comparison. The
  stale cached Python-shell path is not the toolchain contract.

- The fresh pinned-shell ordinary retry returned zero in 671.32 seconds. The
  source suite passed 341 tests and 28 subtests; all six Nix suites passed 187
  checks. The full model was excluded. Original source and suite XML, logs,
  exact commands and runtime inputs are in `build/t15-clean-acceptance-darwin/`.
- Fresh runtime assembly is `w9gq5ixswhvpv2hb08vlh2andqxxhip0`; the compiler
  reports Lean 4.34.1 and Lake 5.0.0-src. The archive used enabled Nix content
  addressing and closure verification and returned zero in 91.35 seconds.
  Its size is 1,113,668,765 bytes and its SHA-256 is
  `1e34f4df1dbd8bcd6c283611383533a14661285bdbe5b6b71629e936176fffb5`.
- Actual fresh-archive installation passed all 27 standard package, Atuin and
  exact T15 nodes in 188.67 seconds, with no skips or errors. Selection used
  `--runtime-variant installed --runtime-archive` without runtime-root. Fresh
  installation and test workspaces, the original XML and both independent
  application-key bundles remain under the clean acceptance directory.
- The addressed runtime is `z7lckizldcb6z54ryzhy616b4f5fw7l8`. Its 106 authored
  runtime files match the checked source. All 116 compiled-library files remain
  byte-identical to assembly; 29 build traces differ only by Nix's addressed
  compiler-path rewrite. XML binds all 145 actual library files, current
  example inputs and the exact trusted-import header. Both fresh keyed bundles
  are 9,390 bytes, with SHA-256
  `a2e63cc3a638a5dca3159d252b5cb3b8afbaddc27ff51fde31da1ed72563fdb4`.
- All 439 selected code/test/example input hashes and seven prior receipt hashes
  still match. Every heavy T15 job is terminal; the Darwin lease is released.
  `acceptance.json`, `ordinary-receipt.json`, `archive-receipt.json` and
  `installed-receipt.json` bind this evidence to checked source `d2d33a6b`
  over approved base `8e10a593`. No performance result is claimed.

## Current integration and remaining acceptance

The clean source's compiler, source, ordinary, example and fresh-archive installed
checks pass. Acceptance checkpoint `f81a666b` passed review
`20261007T094341Z-f81a666b`; metadata integration `95c227f4` passed review
`20261007T094902Z-95c227f4`. Both have no findings. The 17 routing checks and
28 subtests passed in 2.97 seconds, without a native build or replay.

Draft [PR53](https://github.com/vihren-dev/sqlite-verifier/pull/53) is attached,
stacked on `tasks/single-sql-executor`. The published head `7f8c5b3c` passed
review `20261007T111901Z-7f8c5b3c`. Its raw row is preserved in this next commit.
Initial head `ddebc40b` triggered run `37612219181`; published `7f8c5b3c`
triggered run `37613635726`. These are initial run identities, not pass claims.
Earlier publication details remain in `build/t15-clean-metadata-integration/`.

The coordinator authorized exact reviewed T05 head
`46bd04b576436cf88d9a4e7b929ecaeede43d217` as the new metadata parent.
The complete hosted job now has 75 minutes; each suite and command cap remains
unchanged. The prior T05 Darwin job in run `37600117584` was cancelled after
1,824 seconds by its former overall guard. Its 42-case bundle pass did not make
that job a pass. New base run `37615200892` was active at this checkpoint:
Linux job `112771743045` and Darwin job `112771743430`. No result is claimed.

Only the raw journal required merge conflict resolution. Both parent row orders
and the pending review are retained, without an undescribed merge ancestor.
The exact 18 T15 paths, all 106 authored runtime inputs and original acceptance
bytes remain unchanged. The 26 routing, actual Nix membership and inner-budget checks pass, with 28
subtests, in 3.69 seconds under a 90-second outer bound. Six suites retain
420 seconds and the model retains 600 seconds. Commands and evidence are in
`build/t15-job-budget-integration/`. Commit review is required before push.
No new native phase or changed proof, runtime, gate or baseline is included.

Feature acceptance remains bound to `8e10a593` plus `d2d33a6b`. The 75-minute
job guard does not extend any inner cap or claim new feature acceptance.
Dependency repository delivery, hosted native checks and T15 delivery remain
pending; T05's separately approved baseline drift still requires its maintainer
exception. No main write or merge has run. No publication-metadata loop follows
the last reviewed push. The task specifies no additional local native platform
gate, and held T07/T18b code remains excluded.
