# Supported execution profiles

The original autocommit profile string is exactly `3.51.0`. The separate SQLx
profile is selected by a validated JSON manifest, described below; bare
`3.46.0` does not implicitly select a runner. Unsupported versions reject.
Lean is independently pinned to 4.33.0.

## SQLite 3.51.0 autocommit

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

Submit each complete statement in script order on one connection, use autocommit,
and stop on the first statement error. Earlier successful statements remain
committed. Explicit transactions and configuration-changing SQL are unsupported.
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

## SQLite 3.46.0 with SQLx 0.9.0

The manifest kind `sqlite-3.46.0-sqlx-0.9.0-wal-normal-optimize-v1` selects the
independently pinned 3.46 grammar and a sealed execution relation. It identifies
the fixed configuration in [the complete capture](atuin-capture.md), including
WAL/NORMAL, foreign keys enabled, the captured compile flags/runtime limits,
SQLx's normal transactional migrator and optimization on close. The manifest
binds the exact ordered prior catalog, target version and description; the
verifier computes the target SHA-384 from original SQL bytes. See
[profile inputs](profile-inputs.md) for its format and rejection rules.

The approved admission predicate must establish that all listed prior versions
have matching successful metadata, the target is pending, both statistics
tables have their exact definitions and the payload consists of supported ADD
statements outside bookkeeping. Readiness is a checked obligation. This profile
does not support concurrent application writers, external schema mutation,
resource exhaustion, interruptions, I/O faults, corruption or crash/power-loss
recovery. Named runner-stage outcomes do not establish a general refinement
theorem for those excluded mechanisms.

The runner begins a transaction, executes the payload, inserts successful
metadata with execution_time=-1, commits, then updates the elapsed duration.
Pre-commit stage errors and payload failure retain original application storage
after rollback. A timing-update or later cache-clear failure may report an error
after commit; a commit-stage error conservatively admits either observation.
Committed outcomes retain old bookkeeping rows and add the exact target record.
Elapsed durations are signed 64-bit values, matching SQLx's integer cast; the
model does not assume the cast can never overflow. Statistics rows may change
at close, but their definitions and every other table remain protected.

Application requirements must handle each modeled outcome explicitly. A reported
runner error does not by itself mean the migration was unapplied. This relation
is a source-informed model, not a proof of the SQLx or SQLite implementations;
finite [payload comparisons](atuin-model-conformance.md) and
[complete runner traces](atuin-runner-conformance.md) state their exact scope and
any fault instrumentation separately.
