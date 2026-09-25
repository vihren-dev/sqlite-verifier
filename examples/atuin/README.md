# Atuin business-preservation example

This example selects the shell migration at Atuin commit
[`5b10eb09c664d316b7384210399b02e6127f4027`](https://github.com/atuinsh/atuin/tree/5b10eb09c664d316b7384210399b02e6127f4027).
It supplies ordinary SQLite schema and migration SQL. It does not import/build
Atuin, integrate with SQLx, or certify a live framework invocation. Proposed
requirements and interpretations still require owner review.

## Database operations

`schema.sql` describes the application history table immediately before the
selected shell migration, retaining its constraints and three explicit indexes.
The two additional implicit indexes derive from PRIMARY KEY and UNIQUE.
This is a pre-ANALYZE application baseline without optimizer statistics, views,
triggers or foreign keys. It is not every existing Atuin installation's schema;
SQLx's private catalog is outside this example.

The history definition follows the upstream
[initial schema](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/migrations/20210422143411_create_history.sql),
[search index](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/migrations/20220806155627_interactive_search_index.sql),
[soft-delete field](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/migrations/20230319185725_deleted_at.sql),
and [author/intent fields](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/migrations/20260224000100_history_author_intent.sql).
The TEXT primary key remains a nullable ordinary rowid-table key; it is not
silently changed into an INTEGER PRIMARY KEY alias.

`migration.sql` contains only the unchanged upstream
[nullable shell ALTER](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/migrations/20260709214605_shell.sql).
The theorem verifies this SQL payload under the declared SQLite model. SQLx is
trusted for migration selection, catalog maintenance and surrounding invocation
behavior; none of those operations is reproduced or certified here. No implicit
framework operation is added by the SQLite profile. Concurrency, resource failures
and crash recovery remain outside the fixed execution model.

## Application meaning and proposed guarantee

The independent [HistoryModel](approved/HistoryModel.lean) contains
pre-migration business histories, with no shell field, SQL values, physical rowids or
bookkeeping records. The pinned source is read for the old fields; the model does
not anticipate features introduced by this or later migrations. Its field
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
Both interpretations read the same old business model. The resulting reader
ignores new columns; it needs no shell-specific logic. The requirement is equality
of the decoded history lists before and after, for every admitted starting state.
List equality currently preserves model row order as well as multiplicity; it is
not a claim about ordering of SQL queries without ORDER BY.

There is no approved target schema shape or new-feature requirement. A different
nullable added column can be proved with the same protected files. Verification
still binds the candidate proof to the actual SQL and resulting schema. A new
interpretation must recover the old model from resulting storage, without access
to a proof-only copy of the old database. This establishes recoverability; it does
not automatically establish that a changed application uses that reader.

The example proves successful completion for every admitted database, so failing
executions are not silently excluded. Nonempty admitted-state witnesses and
complete decoding guard against impossible assumptions and lost records. The
business model deliberately abstracts storage details; equality does not protect
unmodeled bytes. SQLx metadata identities and rowid-allocation assumptions are no
longer part of the contract.

The full pinned application revision also has the later `author_kind` field;
this example covers the selected intermediate migration, not compatibility with
every query at the pinned revision. The source-backed abstraction is not a formal
proof of the Rust decoder or its external libraries. Correctness of the new shell
feature is separate from preservation of the old history information.

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
It runs the supplied payload on empty and populated application fixtures and
checks that the old stored rows are unchanged. Finite native tests do not prove
universal native-engine refinement or owner acceptance. Adapted upstream SQL
retains Atuin's [MIT notice](UPSTREAM-LICENSE).
