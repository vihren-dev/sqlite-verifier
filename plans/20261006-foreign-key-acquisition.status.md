# Foreign-key acquisition recovery status

Status: DONE. Created and completed 2026-10-06.

Task: [foreign-key acquisition recovery](20261006-foreign-key-acquisition.task.md).
Source: [issue #34](https://github.com/vihren-dev/sqlite-verifier/issues/34).
Specifications: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md),
[execution profiles](../docs/execution-profile.md).

Relevant files: `conformance/native_acquisition.py`,
`conformance/native_record.py`, `conformance/upstream_proxy.tcl`,
`conformance/upstream_assertions.py`, `conformance/upstream_fidelity.py`,
`conformance/execution_profile.py`, `tests/conformance_source_profiles_test.py`.

## Progress

- 2026-10-06: Created an isolated Jujutsu workspace on reviewed support commit
  `ef2cc19e`. Read the issue and pinned SQLite source. The current authorizer
  refuses an FK write in any setup prefix, even when the source later restores
  the original setting. The pinned test restores ON after its OFF/transaction
  checks without resetting the database. Started a bounded unchanged-source
  acquisition in `build/fk-acquisition-before` before code changes.
- 2026-10-06: Selected bounded recovery through faithful setup replay and real
  setting readback. The case profile remains fixed during assertion execution.
  Coordinated shared conformance edits with the transaction and storage tasks;
  Linux storage measurements and retained T03 evidence remain separate.
- 2026-10-06: The authorizer now allows FK writes during setup and inside an
  open transaction. Existing boundary and per-statement readback still enforce
  the selected profile. Three pinned Tcl cases cover real OFF history,
  restoration with retained orphan-row dependencies, real reset, open-transaction
  refusal, and both directions of transaction-local no-op writes. Documentation
  describes the setup/case boundary; no wire format or frozen corpus changed.

## Validation and review

- Unchanged acquisition reproduced 2 recorded assertions out of 940 and 643
  FK-setting refusals. The source hash is
  `424c860b2b9e16f5b3fe9440cd86ea98304913fd9edf25f93b51738a7e06740c`.
- Focused real Tcl checks: 6 passed in 1.26 seconds, bounded by 90 seconds.
- Sandboxed `tests.upstream`: 61 passed in 2.67 seconds, with no skips. JUnit:
  `/nix/store/67knrwqs8pcbrwzm5zjm6sn1b97kwk88-sqlite-verifier-test-upstream-1/junit.xml`.
- Native profile, record, context, fidelity and clock checks: 32 passed in
  1.35 seconds, bounded by 90 seconds. The resolved existing conformance runtime
  is `/nix/store/2pm5l48v8lk5v3p1yqbc3hx3jj1w2ylr-sqlite-verifier-conformance`.
- The uncapped after-change acquisition runs with a 1200-second limit and
  fresh native replay for every admitted case. Its output stays in
  `build/fk-acquisition-after` until the source-bound report is complete.
- 2026-10-06: The full after acquisition completed with 514 admissions out of
  940. All admitted cases passed fresh replay. The old authorizer applied to
  these same 514 original SQL inputs admits 2 and refuses 512 for FK writes.
  [The yield report](../reports/20261006-foreign-key-acquisition.md) accounts for
  the remaining 426 refusals and distinguishes the source's random Tcl loop
  from the exact paired admission check.
- 2026-10-06: Claude reviewed `9390c778` with zero must findings and one should
  finding (`20261006T093937Z-9390c778#1`). The helper docstring now explains the
  permission and the checks that make it safe; its resolution is logged.
- 2026-10-06: A real pinned Tcl regression demonstrated that failed resets can
  create rows before erroring, yet the old proxy discarded that context. The
  proxy now names that refusal and also refuses unretained `SETUP_SQL` after
  successful resets. A later plain successful reset restores eligibility.
  The negative test failed before the guard, then passed with it.
- Final sandboxed upstream suite: 63 passed in 2.51 seconds, with no skips.
  JUnit is `/nix/store/ra19ap3r7afqkw6ahhq74mr4id28gb0c-sqlite-verifier-test-upstream-1/junit.xml`.
- A separate fixed-seed diagnostic compares the old and new reset capture on
  the unchanged pinned source. Its 5,432,796 event bytes match exactly, SHA256
  `080d3368c06bbf3d348d6e91bfd40bed99316275a90632b524315801f3538753`.
  The seed is diagnostic only; source acquisition behavior is unchanged.
- Full acquisition artifacts remain under `build/fk-acquisition-{before,after}`;
  reset events are in `build/fk-reset-equivalence`, and the one-off report and
  paired-check scripts are in `build/fk-acquisition-diagnostics`.
- 2026-10-06: Claude reviewed reset correction `aade8373` with no findings
  (`20261006T095954Z-aade8373`). Corrected the report's command limits to match
  the actual baseline (900 seconds) and after run (1200 seconds). Report checks
  confirm all 940 dispositions, 514 paired admissions, reason totals and matching
  seeded event digests.
- 2026-10-06: Final evidence-note commit `88478fd5` passed Claude review with
  no findings (`20261006T100107Z-88478fd5`). All findings are resolved and the
  task is DONE. The last append-only review entry remains in the working copy
  for the next integration commit, as required by the review workflow.
- 2026-10-06: The ordinary integration check now passes after the approval
  service became available. Command: `nix develop path:./nix --command timeout
  1200 just test`. Source checks pass 327 tests and 28 subtests in 45.40
  seconds. All six development Nix targets pass: Atuin, bundle, CLI, kernel,
  sample and upstream. The command exits 0. Its complete log is
  `build/t16-integration-check.log`; source JUnit is
  `build/test-results/source.xml`. The model target is excluded from this
  ordinary command, as the task does not change model behavior.
- 2026-10-06: Integrated merged main `e9fd9533`. The merge adds no source
  changes to the checked T16 implementation and retains its final review
  entry. Preparing a pull request with the source-bound acquisition report.
