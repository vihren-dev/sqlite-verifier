# Approved exporter: publication integration

The owner approved PR #47 at exact reviewed head `07dc71b3` on 2026-10-07.
This integration combines its recorded approval with merged approved Lean
upgrade `bc9e2dce`. Every checked exporter, prepare/import-view, pin, baseline
and historical receipt file remains byte-exact: 101 files, with the deleted
lean4export patch still absent. Only the journal conflicted; all original
contents, orders and multiplicities remain. The parents contain 28 and 71 rows,
with 18 shared inherited rows; the merge retains 81 rows without duplication.

The approved Lean/exporter, parser and conformance source/derivation identities
remain equal on both native platforms. Main independently updates
`migration_check/sql_model.py` and `profiles.py` for engine settings. Therefore
the combined runtime identity differs from the historical T02 receipt. The
current runtime and its headers/hashes are recorded separately here.

Only the fresh Darwin runtime assembly was built over the unchanged reviewed
Lean/exporter artifacts. Its 12 existing exporter/import-view tests pass without
skips in 52.78 seconds, retaining their original child timeouts and a
420-second group bound. All three actual fixed T03 comparisons pass:

| Fixed input | Bundle bytes | Kernel result |
|---|---:|---|
| Small | 11,358 | VERIFIED |
| Refutation | 14,584 | VIOLATED |
| Atuin | 1,541,403 | VERIFIED |

The bundle SHA-256 values and original input hashes match the immutable T03
receipt. The library-like caller declaration is exported and verified; the
transitive-origin omission and real trusted-file collision tests also pass.
Three actual Nix command/both-platform routing checks pass in 8.50 seconds,
and six CI-routing checks pass in 0.61 seconds. Main's model600/default420
policy remains intact with complete test ownership and reporting.

[summary.json](summary.json) records actual current runtime/executable paths,
headers, hashes and original test outcomes. [approved-files.json](approved-files.json)
records unchanged approved bytes and removal; [source-identities.json](source-identities.json)
keeps approved versus current identities for both systems.
[raw-current-inputs.json.gz](raw-current-inputs.json.gz) retains seven exact
UTF-8 payloads: three original JUnit files and four newly produced bundles.
[raw-sha256.json](raw-sha256.json) binds their original bytes. These current
payloads and the aggregate hashes were verified after capture.

Historical both-platform T03/T02 receipts remain immutable at their recorded
source/runtime revisions. Linux's current runtime identity was evaluated, not
freshly built or tested for this integration. Hosted CI will cover the combined
source. No complete local full-model, ordinary or offline-installed suite was
rerun, and no performance measurement ran.
The task remains IN PROGRESS until normal PR delivery; no merge or release
occurred, and PR #48/#50 heads remain unchanged.
