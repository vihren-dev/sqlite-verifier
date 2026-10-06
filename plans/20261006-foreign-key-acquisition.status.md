# Foreign-key acquisition recovery status

Status: IN PROGRESS. Created 2026-10-06.

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
