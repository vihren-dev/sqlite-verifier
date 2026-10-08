# Grouped immediate-transaction evidence

Audience: model and native-evidence reviewers.

[Issue #36](https://github.com/vihren-dev/sqlite-verifier/issues/36) adds five
neutral groups in [authored_transactions.py](../conformance/authored_transactions.py).
Each group executes `BEGIN IMMEDIATE` and multiple statements on the same writer
connection. The recorder observes committed storage through a separate connection
while the transaction is open. Native records retain typed bindings, columns,
rows, direct change counts, primary/extended codes and both database views at
each reached statement.

| Case | Checked boundary |
| --- | --- |
| `immediate-schema-write-commit` | Added default column, explicit index, INSERT and UPDATE stay writer-visible until COMMIT publishes the complete group. |
| `immediate-schema-write-rollback` | ROLLBACK removes the created table and restores the updated starting row. |
| `immediate-savepoint-rollback` | ROLLBACK TO removes inner schema/writes, preserves the earlier insert, and leaves the outer transaction open through RELEASE. COMMIT publishes the retained prefix. |
| `immediate-check-abort` | CHECK failure has primary code 19 and extended code 275, zero direct changes, and no partial row insertion. Earlier writes remain visible and uncommitted. |
| `immediate-deferred-commit-failure` | Failed COMMIT has primary code 19 and extended code 787. Pending child data stays visible to the writer; the committed observer has no child rows. |

Both failures stop execution at their fourth statement. Later SQL remains in
the recorded source but does not run. Successful DML retains its exact typed
parameters and direct counts. Schema/transaction/read operations have no direct
DML count. The savepoint scenario also checks that the temporary column disappears.

The [published additions](../reports/20261006-grouped-immediate-transactions/manifest.json)
use a separately named corpus, version 1, with native acquisition version 4 and
the existing shared-snapshot/shard transport. Its manifest binds all five records,
the measured profiles and the definition source digest. Its stored payload digest
is `5c803913c7e356255d0c1bd1d9ccaf328ffbbac8e86aadbe63580dc68cb6830a`.
Historical definitions and frozen corpora v1–v5 keep their existing identities.
Scenario tags carry no requirement credit; production model support is unchanged.

Create another evidence directory and replay it in the pinned environment:

```sh
nix develop path:./nix --command timeout --foreground 60 \
  python3 -m conformance.transaction_evidence --output build/immediate-transactions
nix develop path:./nix --command timeout --foreground 60 \
  python3 -m pytest tests/conformance_authored_transactions_test.py \
  tests/conformance_transaction_evidence_test.py
```

Publication acquires fresh records, replays them, writes ordinary corpus bindings,
loads the resulting shard and replays it through new connections. An existing
output directory is refused. The tests compare the retained records with fresh
acquisition, check concrete state/output boundaries, and reject an altered
transaction flag or committed snapshot. Stored pool corruption and unbound
shard changes fail before replay. The Nix harness target owns acquisition checks;
the frozen target owns the retained evidence checks and report inputs.
Native statement execution has a five-second
deadline; the example commands have a 60-second limit.
