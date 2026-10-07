# Native evidence for grouped immediate transactions

Created 2026-10-06. Status: DONE. Completed 2026-10-07.
Status file: [status](20261006-grouped-immediate-transactions.status.md).
Source: public [issue #36](https://github.com/vihren-dev/sqlite-verifier/issues/36).

## Observable behavior when done

Additional neutral authored scenarios execute actual multi-statement
`BEGIN IMMEDIATE` groups. They cover schema/write/read changes followed by
successful commit, explicit rollback, rollback to a savepoint, and an intentional
constraint failure. A deferred foreign-key COMMIT failure also records the
still-open transaction and stops at that first error.

Every reached statement retains its SQL, typed parameters, output columns and
rows, direct change count, primary/extended result codes, transaction-open flag,
writer-visible state and independently observed committed state. The evidence
shows pre-commit isolation, commit publication, complete explicit rollback,
savepoint rollback that preserves the earlier prefix, and statement atomicity
that preserves prior successful writes after a constraint error.

New definitions and published evidence are separate from historical authored
definitions and frozen corpora v1–v5. Existing model support and admission stay
unchanged. Scenario tags claim no requirement or SQL coverage credit.

## Acceptance tests and evidence

- Acquire the new cases with the pinned native engine. Assert concrete outputs,
  typed bindings, direct counts and both database views at relevant boundaries.
  Failed statements/COMMIT retain exact failure codes and open transaction
  state; statements after the first failure never execute.
- Store, load and freshly replay the new shard using ordinary digest-bound
  corpus and shared-snapshot transport. Retain a separately published evidence
  directory with measured profile identities and a reproducible acquisition
  command. It refuses overwriting an existing output.
- Altering a transaction-open flag or an independently committed snapshot fails
  fresh replay. Altering a stored snapshot or boundary without updating its
  binding fails storage validation. Existing historical definition counts and
  corpus hashes stay unchanged.
- Run the affected authored/native/storage suites through the pinned Nix
  development environment and wire the new checks into the model Nix target.
  Tests and native calls have bounded timeouts. No Linux performance measurement
  belongs to this task.

## Relevant code and constraints

`conformance/authored_cases.py` supplies `AuthoredCase`, measured profiles and
native `records`. `native_record.py` observes the writer and a separate reader;
`native_statements.py` uses SQLite statement tails, parameters and a five-second
deadline, and stops on the first error. `corpus_shards.py`, `native_storage.py`
and `corpus.native_replay` already provide publication, validation and replay.
Use these shared paths without changing transaction semantics or old catalogs.

Savepoints and additional schema forms may remain production-model unsupported.
The profile's immediate label must agree with actual BEGIN SQL. Statement-level
ABORT differs from rollback of the outer transaction. Deferred foreign-key
COMMIT failure leaves pending data visible only to the writer.

## Delivery

[PR55](https://github.com/vihren-dev/sqlite-verifier/pull/55) merged normally
as `923b7cee` after current-head Linux CI and retained native macOS
acceptance. The fetched merge tree exactly matches tested head `c26e0257`.
All five groups and all 13 new checks are delivered. Historical definitions
and frozen corpus bytes remain unchanged.
