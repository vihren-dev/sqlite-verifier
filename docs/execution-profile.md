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
build with DQS=0 and an effective column limit of 2000. No extensions, custom
authorizers, concurrent connections, application callbacks, or custom collations
may change supported statement behavior. Writable-schema mode is off. Other
SQLite resource limits must not interrupt the modeled execution.

Submit each complete statement in script order on one connection and stop on
the first statement error. Statements outside explicit transactions use
autocommit. Transaction operations must appear in the supplied SQL; no framework
rollback, bookkeeping, cache handling or connection-close maintenance is added.
Configuration-changing SQL remains unsupported. See the semantic subset for
the exact admitted transaction and data-operation forms.
The verifier does not run migrations and cannot inspect a live connection to
enforce these assumptions. A future execution command would need that boundary.

The model includes table-exists, missing-table, duplicate-column, and column-limit
errors. It excludes interruptions, memory/disk/resource exhaustion, corruption,
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
