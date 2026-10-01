# Supported execution profiles

The supported version strings are `3.51.0` and `3.46.0`. Both select SQLite
semantics without a migration framework. Unsupported versions reject.
Lean is independently pinned to 4.33.0.

## Pinned SQLite configuration

Native evidence uses the official SQLite
source ID `fb2c931ae597f8d00a37574ff67aeed3eced4e5547f9120744ae4bfa8e74527b`,
with source/archive hashes recorded under `parser/upstream/` and Nix.

The semantic subset is described in [semantic-subset.md](semantic-subset.md).
It assumes one ordinary main database, valid SQLite storage, ordinary rowid
tables, only the admitted schema objects, no ambient transaction, and the pinned default
build with library-default DQS_DML=1 and DQS_DDL=1 and an effective column limit of 2000. No extensions, custom
authorizers, concurrent connections, application callbacks, or custom collations
may change supported statement behavior. Writable-schema mode is off. Other
SQLite resource limits must not interrupt the modeled execution.

Double-quoted tokens in expression positions may fall back to string literals in
SQLite. The frontend conservatively rejects such literal/assignment expressions
as `UNSUPPORTED`; quoted identifiers that resolve to declared columns remain
usable. This implements the [ADR 0004 owner decision](adr-0004-model-conformance-validation.md).
Native C-API connections verify both defaults without overriding them. The shell
runner explicitly enables both settings because the shell starts with DQS off.

Submit each complete statement in script order on one connection and stop on
the first statement error. Statements outside explicit transactions use
autocommit. Transaction operations must appear in the supplied SQL; no framework
rollback, bookkeeping, cache handling or connection-close maintenance is added.
Configuration-changing SQL remains unsupported. See the semantic subset for
the exact admitted transaction and data-operation forms.
The verifier does not run migrations and cannot inspect a live connection to
enforce these assumptions. A future execution command would need that boundary.

The model includes table-exists, missing-table, duplicate-column, column-limit,
transaction-already-active, no-active-transaction, and supported constraint errors. It excludes interruptions, memory/disk/resource exhaustion, corruption,
I/O errors, process crashes, power loss, and interference. It makes no crash or
whole-script rollback guarantee. Applicability and every modeled outcome remain
explicit proof obligations under the supplied approved contract.

## Shared storage model

Schemas record normalized object names, ordered columns, supported declarations,
affinities, nullability, defaults, keys and indexes. Preserving an existing key's
old column projections preserves any predicate over those projections; this
does not introduce an unproved native comparator or broaden CREATE support.
Database values include NULL, integer, opaque real payloads, UTF-8-independent
text bytes, and blobs. These value domains are conservative: this release does
not prove native float encoding, coercion rules, schema-text identity, pragmas,
schema-cookie values, physical layouts, or arbitrary application queries.
Additive statements preserve old values without evaluating or converting them.
Physical rowids are unique signed 64-bit values; rowid-shadowing columns are
rejected. Logical projection helpers retain row identity and every designated
cell; native observation tests explicitly order by rowid.

Native correspondence is supported by pinned documentation and
tests, separately from Lean proof acceptance. The SQLite C implementation has
not been formally verified. Coverage and exclusions are reported separately in
[upstream fixture evidence](conformance-fixtures.md) and
[derived model comparisons](conformance-model.md).

## SQLite 3.46.0

The additional release uses official source ID
`96c92aba00c8375bc32fafcdf12429c58bd8aabfcadab6683e35bbb9cdebf19e`.
Its source/archive hashes are recorded under `parser/upstream-3.46.0/` and Nix.
The same supported SQL subset and fixed assumptions apply; differences in the
full grammar remain checked against the separately pinned parser. Selecting
this version does not select SQLx or impose a migration-history catalog.

## Native corpus profiles (ADR 0005, in progress)

Explicit native evidence carries a named, versioned profile with measured engine
version, source ID and the complete sorted compile-option list. Behavioral
settings currently include foreign-key enforcement and recursive triggers; they
are established and read back before case SQL runs. The profile names the
deferred or immediate transaction convention; SQL must use that convention.
Ignored settings carry reasons, and assumptions about other writers are recorded.

Clock input is either excluded or `unix-milliseconds-v1`. In the latter mode,
recording requires a setup timestamp and one timestamp per reached statement.
A private VFS delegates native filesystem operations and supplies both SQLite
time callbacks. Defaults, trigger bodies and supplementary probes therefore see
the same engine time. Replay supplies the recorded inputs and refuses a different
profile. Valid explicit-profile evidence stays model-unsupported until production
semantics can execute that profile. Existing frozen records retain their old path.
Controlled profiles also record `timezone: UTC`: recording/replay temporarily
establish UTC for native `localtime` conversion and restore the caller's timezone.
Recording is serialized while this process-global setting is active; parallel
recording should use worker processes. Other timezone profiles are refused.
Setting PRAGMAs outside the profile are refused. Explicit boolean writes that
already match the profile are accepted and their settings are read back after
SQL execution. Ignored settings may name
`journal_mode`, `synchronous`, `cache_size`, `temp_store`, `mmap_size` and
`busy_timeout`, each with a reason; behavioral settings cannot be labelled ignored.
Corpus manifests declare full records in `executionProfiles`; every v4 case
must match one declaration exactly. Missing/conflicting records and duplicate
name/version identities are refused. Legacy manifests retain implicit profiles.

### Measuring a workload's engine builds

For each driver the application ships, build a small measurement command using
that driver's exact module version, build tags and connection initialization.
Run it on each shipped platform. On the opened driver connection, collect
`SELECT sqlite_version(), sqlite_source_id();` and every row of
`PRAGMA compile_options;`, sorted. Read back behavioral settings such as
`PRAGMA foreign_keys;` and `PRAGMA recursive_triggers;` after application setup.
Read the effective column limit on that same connection through the driver's
limit API or `sqlite3_limit(db, SQLITE_LIMIT_COLUMN, -1)`. Query it without
changing it. `MAX_COLUMN` in the compile options gives the ceiling; it does not
show whether the application lowered the connection's limit. The current
recorder establishes and verifies 2000. A workload with another effective limit
needs a supported profile before its suite can be completed.
Retain the driver dependency lock, command, build configuration and outputs
beside the external workload profile. A system sqlite3 shell or package version
does not measure the engine linked into a driver.

Compare those measurements with the pinned recorder engine. Any version/source
or compile-option difference remains an explicit gap until its effect on the
workload SQL is checked. Add a source-pinned engine when the difference affects
that SQL; do not relabel evidence from another build. Before measurements exist,
state that evidence uses the pinned engine and the workload-engine gap is
unmeasured. Workload identities and measurement artifacts stay outside the core.
