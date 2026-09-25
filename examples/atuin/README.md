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

The independent [HistoryModel](approved/HistoryModel.lean) contains business
histories, with no SQL values, physical rowids or bookkeeping records. Its field
mapping follows Atuin's [History definition and UUID decoder](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/src/history.rs#L217-L343)
and [database decoder](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/src/database.rs#L287-L318):

| Business field | Stored column and interpretation |
|---|---|
| `id` | `id`: application UUID identity, admitted as canonical 32 lowercase hexadecimal characters. |
| `timestampNanos` | `timestamp`: signed 64-bit Unix nanoseconds. |
| `durationNanos` | `duration`: signed 64-bit nanoseconds; negative values, including the unfinished-command sentinel, remain representable. |
| `exit` | `exit`: signed 64-bit status. |
| `command`, `cwd`, `session` | Corresponding UTF-8 text; session is not required to be a UUID. |
| `origin` | `hostname`: split at the first colon into host/user; without a colon, user is `unknown-user`. |
| `author` | Nonblank author text, otherwise hostname's user component; without a colon, the fallback is the original hostname. |
| `intent` | Nullable text; Unicode-whitespace-only text becomes absent. |
| `deletedAtNanos` | `deleted_at`: absent or signed 64-bit Unix nanoseconds. |
| `shell` | Missing before migration means unknown; afterward SQL NULL means unknown, and text remains unchanged, including empty or whitespace-only strings. |

Nonblank author and intent retain surrounding whitespace: upstream tests
trim-emptiness without replacing the original text. The
[database builder](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/src/history/builder.rs#L138-L155)
does not apply capture-time normalization. Host/user handling follows
[CmdOrigin](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-domain/src/record/cmd_origin.rs#L133-L182).
The entire signed nanosecond timestamp range is supported by upstream's
[time conversion](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-common/src/time/offset_date_time.rs#L107-L125);
[duration display and recording](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin/src/command/client/history.rs#L320-L321)
also use nanoseconds.

[HistoryDecoding](approved/HistoryDecoding.lean) is a partial, all-row decoder.
It rejects the entire observation if a row has missing required columns, invalid
UTF-8, noncanonical UUID text, wrong storage classes or out-of-range integers.
It never filters out bad rows. This is an explicit conservative admitted domain:
upstream accepts additional UUID spellings and swallows optional field decoding
errors, whereas this example requires optional stored fields to be valid TEXT/NULL
(or INTEGER/NULL for deletion time). Nullable SQL primary keys therefore do not
imply that NULL application identifiers satisfy this interpretation.

The approved interpretation is pinned to the sealed translation of `schema.sql`.
Its field mapping names columns without duplicating their full SQL declarations.
The before reader maps missing shell to unknown, and the after reader decodes
actual shell cells. The proposed business requirement is equality of the decoded
history list. `Requirements.resultValid` independently applies the approved
mapping to actual before/after databases, so a candidate reader cannot hide a
changed business value or invent a missing shell value.

Bookkeeping belongs to representation invariants, not the business `History`
type. The example-only approved [AtuinCatalog](approved/AtuinCatalog.lean) requires
exactly six successful version/checksum identities before and those six plus the
selected target afterward. The generic SQL proof and finite native tests can
establish stronger storage facts, including unchanged old metadata and physical
rowids; those facts are not independent business requirements. Normal metadata
rowid allocation is admitted only below the signed maximum; the native random
fallback is outside the modeled INSERT domain.

These are proposed requirements for owner review. The typed proof bundle passes
the public CLI with its protected schema/source baseline and only the permitted
foundational Lean axioms. The full pinned application revision also has the later
`author_kind` field; this example covers the selected intermediate migration,
not compatibility with every query at the pinned revision. The source-backed
abstraction is not a formal proof of the Rust decoder or its external libraries.

## Checking

From the repository root, using the declared SQLite environment:

```sh
bin/migration-check verify --profile 3.46.0 \
  --schema examples/atuin/schema.sql \
  --requirements examples/atuin/approved/Requirements.lean \
  --interpretation examples/atuin/approved/Interpretation.lean \
  --migration examples/atuin/migration.sql \
  --next-interpretation examples/atuin/NextInterpretation.lean \
  --proofs examples/atuin/Proofs.lean \
  --approved-baseline examples/atuin/approved/baseline.json --format json
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
