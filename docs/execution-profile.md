# SQLite 3.51.0 execution profile

The required profile string is exactly `3.51.0`. Another syntactically valid
version is `UNSUPPORTED`; a missing or malformed version is `INPUT_ERROR`.
Lean is independently pinned to 4.33.0. Native evidence uses the official SQLite
source ID `fb2c931ae597f8d00a37574ff67aeed3eced4e5547f9120744ae4bfa8e74527b`,
with source/archive hashes recorded under `parser/upstream/` and Nix.

The semantic subset is described in [semantic-subset.md](semantic-subset.md).
It assumes one ordinary main database, valid SQLite storage, ordinary rowid
tables, no extra schema objects, no ambient transaction, and the pinned default
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

Schemas record normalized object names, ordered columns, and canonical affinities.
Database values include NULL, integer, opaque real payloads, UTF-8-independent
text bytes, and blobs. These value domains are conservative: this release does
not prove native float encoding, coercion rules, schema-text identity, pragmas,
schema-cookie values, physical layouts, or arbitrary application queries.
Additive statements preserve old values without evaluating or converting them.
Physical rowids are unique signed 64-bit values; rowid-shadowing columns are
rejected. Logical projection helpers retain row identity and every designated
cell; native observation tests explicitly order by rowid.

The profile's native correspondence is supported by pinned documentation and
tests, separately from Lean proof acceptance. The SQLite C implementation has
not been formally verified. Coverage and exclusions are reported separately in
[upstream fixture evidence](conformance-fixtures.md) and
[derived model comparisons](conformance-model.md).
