# Clean transaction integration checks

Audience: task reviewers.

The [receipt](receipt.json) binds the focused checks to the reviewed executor
base `46bd04b5`. The four original JUnit files report 98 passing checks with
no failures, errors or skips. The Nix selection deselects 41 unrelated checks.
It executes the real suite command check and all six new input invalidations.

The native checks use the pinned development environment. The historical
authored checks use the retained conformance runtime named in the receipt.
Actual Nix evaluation of this clean integration produces that exact runtime
path. T13 adds no Lean or parser input. This is a runtime identity check,
not a claim that the runtime was built again.

The historical transaction shard and all 16 evidence and diagnostic files are
byte-identical to `t13-mixed-history-acceptance`. The review journal preserves
both source histories in order, including repeated rows. All existing base
files outside the four explicitly listed input and journal changes remain
unchanged. New task files, tests and evidence are separate additions.

These focused checks do not establish complete model acceptance. The actual
model derivation and its unchanged 600-second pytest limit remain required.
The old unfinished run and limited diagnostic failures remain qualified in
the task's [status](../../plans/20261006-grouped-immediate-transactions.status.md).
