# Atuin shell-column SQL example

This example selects the shell migration at Atuin commit
[`5b10eb09c664d316b7384210399b02e6127f4027`](https://github.com/atuinsh/atuin/tree/5b10eb09c664d316b7384210399b02e6127f4027).
It supplies ordinary SQLite schema and migration SQL. It does not import/build
Atuin, integrate with SQLx, or certify a live framework invocation. Proposed
requirements and interpretations still require owner review.

## Database operations

`schema.sql` describes a reasonable intermediate database immediately before the
selected shell migration: history, its three explicit indexes, and bookkeeping.
The three additional implicit indexes derive from the retained PRIMARY KEY and
UNIQUE declarations. This is a pre-ANALYZE baseline without optimizer statistics,
views, triggers, foreign keys or other application objects. It is not asserted
to be every existing Atuin installation's schema.

The history definition follows the upstream
[initial schema](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/migrations/20210422143411_create_history.sql),
[search index](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/migrations/20220806155627_interactive_search_index.sql),
[soft-delete field](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/migrations/20230319185725_deleted_at.sql),
and [author/intent fields](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/migrations/20260224000100_history_author_intent.sql).
TEXT and BIGINT primary keys remain nullable ordinary rowid-table keys; neither
is silently changed into an INTEGER PRIMARY KEY alias.

`migration.sql` has five explicit statements: BEGIN, the unchanged upstream
[nullable shell ALTER](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/migrations/20260709214605_shell.sql),
a bookkeeping INSERT, COMMIT, and an elapsed-time UPDATE. Their order reflects
SQLx's [apply and execute_migration implementations](https://github.com/launchbadge/sqlx/blob/003b698e99e024f3621b8043a2426fde5b741171/sqlx-sqlite/src/migrate.rs#L150-L274);
that file also defines the bookkeeping table. Atuin's
[lockfile](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/Cargo.lock)
pins SQLx 0.9.0. The SQLx release source identifies that source commit.

The version is 20260709214605 and description is `'shell'`. The checksum literal
is SHA-384 of the original 42-byte ALTER file, including its final newline—not
of this five-statement wrapper. SQLx normally obtains installed_on from the
CURRENT_TIMESTAMP default. This example explicitly inserts `'2026-09-25 00:00:00'`
as one concrete instantiation of that clock value, and fixes the post-commit
elapsed parameter at 1000000 nanoseconds. It does not claim those values were
measured from an application execution. The initial execution_time remains -1,
and the INSERT deliberately omits physical rowid so SQLite allocates it.

This is a database-effect instance of the selected migration transaction and
its timing update. It excludes framework readiness queries/catalog decisions,
connection setup, cache management, pool closure/optimization, concurrent writers
and crash recovery. It does not reproduce every SQLx outcome. In particular,
plain BEGIN/COMMIT SQL does not encode a framework's implicit rollback on error;
failed SQL is interpreted under the verifier's explicit SQLite execution policy.
No omitted framework operation is silently added by the SQLite version setting.

## Application meaning and proposed guarantee

Atuin's [History fields](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/src/history.rs#L313-L339)
represent commands, execution time/duration/status, location/session/host,
soft deletion, author/intent, and an optional shell. The
[database decoder](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/src/database.rs#L287-L318)
reads missing or NULL shell as None. The
[shell filter](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/src/database.rs#L163-L188)
uses SQL NULL to represent commands without recorded shell information.

The proposed logical history preserves all eleven old stored fields and physical
row identities. Before migration, the missing shell field is normalized to the
same logical unknown/NULL value represented afterward by a stored SQL NULL.
`Requirements.change` (Q) preserves this logical history. The resulting reader
reads actual shell values; it does not invent NULL values independently of storage.

The approved [requirements](approved/Requirements.lean) also define
`Requirements.resultValid`, which checks the actual resulting shell projection
and requires every existing row's shell to be NULL. The contract's outcome
applicability requires this predicate. That independent storage check prevents a
candidate constant reader from hiding incorrect shell initialization, even if its
logical output appears to satisfy Q.

These are proposed definitions for owner review; the revised SQL-only proof bundle
is still being checked. The intended declarations are
`Interpretation.admitted` and `Interpretation.current.invariant` in the approved
[initial interpretation](approved/Interpretation.lean), and
`NextInterpretation.next.invariant` in the candidate
[resulting interpretation](NextInterpretation.lean).
The logical state contains normalized history and actual bookkeeping rows.

The example-only approved [AtuinCatalog](approved/AtuinCatalog.lean) supplies
`prior`, `target`, `recorded`, and `Invariant`. The initial invariant requires
exactly six successful version/checksum identities; the resulting invariant
requires those same six plus the selected successful shell migration. Old
metadata fields and physical rowids remain arbitrary within the generic admitted
SQLite data domain. The SQL's INSERT and UPDATE must preserve all old records and
produce the explicit new record. These catalog conditions are application
requirements, not fields in the core engine profile or implicit SQL operations.

Preserving old history fields preserves inputs to the application's decoder and
filters; unknown shell continues to mean “shell not recorded.” This is a storage
and interpretation guarantee, not a formalization of the Rust decoder, UUID
validity, timestamp conversions, author fallback/normalization, or every query.
The full pinned revision's HISTORY_COLUMNS also includes later author_kind;
this example covers the selected intermediate migration and does not promise
compatibility with every query at that revision. Native edge-case fixtures need
not all be decodable as History.

Bookkeeping insertion, constraints, rowid allocation and timing update use
generic SQL semantics and explicit data assumptions. Ordinary rowid allocation
is admitted when the metadata table's maximum physical rowid is below the signed
64-bit maximum; negative maxima and empty tables retain SQLite's actual behavior.
The random allocation fallback at the maximum lies outside that modeled domain.

## Checking

From the repository root, using the declared SQLite environment:

```sh
bin/migration-check verify --profile 3.46.0 \
  --schema examples/atuin/schema.sql \
  --requirements examples/atuin/approved/Requirements.lean \
  --interpretation examples/atuin/approved/Interpretation.lean \
  --migration examples/atuin/migration.sql \
  --next-interpretation examples/atuin/NextInterpretation.lean \
  --proofs examples/atuin/Proofs.lean --format json
```

The ordinary native SQL comparison is separate evidence from proof status.
It runs the supplied SQL on empty and populated history fixtures, preserving
independent expected values and checking schema/bookkeeping effects. Finite
native tests do not prove universal native-engine refinement or owner acceptance.
Adapted upstream SQL retains Atuin's [MIT notice](UPSTREAM-LICENSE).

The native fixture metadata is deliberately minimal and differs from the approved
proof example. These are generic SQL-mechanics checks, not witnesses of the
Atuin interpretation invariant or a complete migration catalog. The MAX_ROWID
case observes native random allocation and is explicitly outside the proposed
deterministic INSERT domain.
