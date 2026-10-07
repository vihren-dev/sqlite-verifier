# Status: native evidence for grouped immediate transactions

Created 2026-10-06. Status: IN PROGRESS.
Task: [task](20261006-grouped-immediate-transactions.task.md).
Source: public issue #36.
Relevant files: `conformance/authored_cases.py`, `native_record.py`,
`native_statements.py`, `corpus_shards.py`, `native_storage.py`, `corpus.py`,
`tests/nix_suites.json`, `build-support/tests.nix`.

## Progress

- 2026-10-06: isolated workspace created from reviewed support commit
  `ef2cc19e7fd107ed50fb02be78d644c88f9a33dd`. Read the public issue, current
  acquisition/authoring/storage paths and applicable instructions.
- 2026-10-06: task and status files created before coding. Coordinated with
  the storage and foreign-key acquisition tasks: new authored/test/evidence
  files avoid their shared recorder/profile changes. Frozen evidence remains
  separate. No Linux timing will run here.

- 2026-10-06: Added five transaction groups and published their separately
  named evidence. The tests check committed storage, rollback, savepoints,
  CHECK failures, deferred foreign-key failures, typed outputs and corrupted
  evidence. Historical definitions and frozen corpora remain unchanged.
- 2026-10-06: The 13 focused tests pass in 1.06 seconds with a 60-second
  command limit. The JUnit receipt is `/private/tmp/t13-targeted-20261006.xml`.
  Both new test files and their inputs are assigned to the Nix model suite.
- 2026-10-06: The earlier full model run reached 328 passing cases but did
  not finish or produce a complete JUnit report. Its log is retained at
  `/private/tmp/t13-model-nix.log`. A formatting error prevented a useful
  final diagnostic. This run is not acceptance evidence.
- 2026-10-06: The owner requested a commit of the existing feature code
  before another limited diagnostic. This commit preserves that work on
  `tasks/grouped-immediate-transactions`. Full model acceptance and the
  independent review remain incomplete.

## Remaining validation

The checkpoint review has no must findings. Its one should finding asks for
named evidence identities. The follow-up names the source, part, version and
kind without changing the published records or manifest.
All 13 focused tests pass again in 1.13 seconds with the same 60-second limit.
The finding is recorded as fixed in the review journal.
The correction review has no must findings and two should findings. Each
constant now has its own description. The retained manifest is also checked
against the named kind and version, so a policy change cannot silently pass.
All 13 focused tests pass again in 1.07 seconds. Both findings are fixed.

The limited diagnostic reads the original failed derivation's log with both
`nix log` and `nix-store --read-log`, each with a 30-second limit. Both return
success and identical output, ending at the v5 progress test. Neither contains
a formatting error. The available test log therefore does not establish that
pytest caused that error. Commands, outputs and hashes are retained in
`/private/tmp/t13-format-diagnostic-20261006/`. A bounded reproduction of the
builder failure will wait until the PR #48 full model run releases the host.

- 2026-10-06: Final correction `e157ec0d` passes independent review with no
  findings. The feature remains on `tasks/grouped-immediate-transactions`.
- 2026-10-06: After the host was released, two limited diagnostics completed.
  A two-second Nix builder limit reports a normal timeout. A separate clone
  of the test derivation, with only a two-second pytest limit, reports normal
  builder exit 124. Neither reproduces `boost::bad_format_string`. These are
  diagnostic failures by design, not acceptance checks. The original full
  log and both diagnostic outputs are retained with hashes in
  [the diagnostic record](../reports/20261006-grouped-immediate-transactions-validation/format-diagnostic.json).
  The formatting failure remains unexplained. Full model acceptance remains
  incomplete, so this task is HELD while the separate timeout task proceeds.

The authorized limited diagnostics are complete. They did not reproduce the
formatting error. Their original outputs remain historical evidence; the
incomplete full model run is not a passing acceptance result.

## Clean integration, 2026-10-07

The timeout correction is merged, and the reviewed executor integration is
available at `46bd04b5`. The old transaction branch also contains model and
exporter changes that would replace newer accepted fixes. Its exact working
copy, including the pending review row, is retained at the local bookmark
`t13-mixed-history-acceptance` (`4ab9f4d8`). No old receipt is replaced.

This workspace now starts directly from `46bd04b5`. Only this task and status
are restored at this planning checkpoint. The transaction definitions, tests,
separate evidence and their Nix inputs will be integrated on that source.
The existing 13-case receipts describe their original source only. Fresh
authored, native and storage checks, actual Nix input ownership, the complete
model target and independent review must establish current acceptance.
Executor source, approved baselines, frozen corpora and all existing command
limits must remain unchanged. The task remains incomplete.

The clean feature now contains only the original transaction definitions,
publisher, two test files, documentation and separate evidence. Model Nix
inputs include both Python modules, both test files and the report directory.
Six new invalidation checks change each of those inputs, including the binary
shard, and inspect the actual derivation identities. They also confirm the
existing seven-suite membership and all 420/600-second command limits.

All 65 transaction, review, storage and shard checks pass in 2.02 seconds.
All 24 historical authored, boundary, query and native checks pass in 8.74
seconds. Both commands have 60-second limits. The seven real Nix checks pass
in 11.77 seconds with a 90-second limit; 41 unrelated checks are deselected.
Both documentation checks pass in 0.48 seconds with a 60-second limit.
The resource guard passes before acceptance. The exact retained conformance
runtime used for historical checks matches actual Nix evaluation of this
clean source. No runtime build is claimed at this checkpoint.

The [focused acceptance receipt](../reports/20261007-grouped-immediate-transactions-integration/README.md)
retains all four original JUnit files, source bindings and scope qualifications.
All 16 original evidence and diagnostic files remain byte-identical. The
journal preserves all 169 base rows and 23 historical rows in order and with
their original multiplicity, using 176 merged rows. Approved executor and
baseline files, all frozen corpora and other existing base files are unchanged.
This feature checkpoint awaits independent review. The complete model target
remains required before current acceptance or task completion is reported.

## Decisions waiting for the owner

- None for the limited diagnostic. The owner authorized it on 2026-10-06.
