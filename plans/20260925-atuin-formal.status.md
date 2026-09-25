# Atuin formal backend extension

Created: 2026-09-25. Status: IN PROGRESS — not DONE.
Task: [unchanged Atuin migration](20260925-atuin-shell-migration.task.md).

## Checked schema unit

`Declarations.lean` retains canonical versus BIGINT/TIMESTAMP/BOOLEAN type
spelling, NOT NULL, existing CURRENT_TIMESTAMP defaults, primary/unique keys and
simple named indexes. `Model.lean` binds stored table properties to the complete
input schema, validates key references and the table/index namespace, and rejects
the single canonical INTEGER PRIMARY KEY rowid alias. Nullable TEXT and BIGINT
primary keys do not gain an unstated NOT NULL condition. Implicit autoindexes
are represented by their originating constraints, not dropped from meaning.

`Execution.lean` still executes only plain canonical columns for CREATE and ADD;
new constrained/defaulted columns cannot silently materialize NULL. Rich-schema
CREATE admission is withheld by the frontend until its global index namespace
semantics are implemented. Existing autocommit outcomes and preservation proofs
remain valid. Existing source literals require named records or defaulted `mk`
applications; protected example syntax/hash updates are integration work and do
not authorize a logical requirement change.

`SchemaPreservation.lean` proves that table extension retains exact declaration
records and all key/index properties, and preserves every supplied predicate of
old key or column projections. The key predicate is universally quantified, so
this does not substitute tagged-value equality for SQLite numeric/NULL/collation
comparison. Model conformance remains a conservative superset of native-valid
stored states, not a constraint validity decision procedure. Native validity of
old states plus the retained definitions/projections supplies the correspondence
argument; the SQL engine itself is not verified by these theorems.

Validation: `timeout 60s lake build` passed all 15 jobs. Structural regressions
cover nullable TEXT key data, BIGINT versus INTEGER primary keys, timestamp
metadata, invalid alias affinity, absent key columns, index/table collisions,
metadata retention, and rejection of constrained new columns. Existing complete
VC theorems and the new generic key-preservation theorem retain only propext,
Classical.choice and Quot.sound.

## Remaining work

Bind SQLite 3.46.0 and SQLx's actual runner policy in sealed generated inputs and
independently reconstructed VCs; preserve legacy 3.51.0 autocommit. The runner
model must distinguish rollback errors from timing-update/cache-clear errors
after COMMIT, and bind catalog/version/checksum readiness explicitly. Add actual
captured-schema proofs and reusable pilot inputs, independent native/model tests,
end-to-end gate checks and installed-package evidence. No pilot verification or
owner acceptance is claimed by this schema unit.

## Persisted statistics schema follow-up

Native SQLx optimize-on-close evidence revealed `sqlite_stat1` and `sqlite_stat4`
in the persisted baseline after the previous six migrations. `DeclaredType`
therefore includes omitted types with BLOB affinity, and existing-schema validity
admits precisely those two engine-defined column/property layouts. This does not
admit arbitrary `sqlite_*` objects or permit migration statements to alter them.
The frontend and complete capture are being updated independently. Statistics
row maintenance belongs in the forthcoming disjoint runner footprint.

Validation: `timeout 60s lake build` again passed all 15 jobs. Additional guards
accept the exact stat1 layout, reject a altered layout, and reject reserved names
as migration targets. No final SQLx proof or package claim is made here.

## Sealed runner configuration types

`RunnerProfile.lean` supplies the agreed migration identity/configuration records,
fixed legacy/SQLx profile constructors, exact bookkeeping declaration, and an
explicit pending-target readiness predicate. Readiness checks the complete prior
catalog/checksum multiset, successful metadata flags, already-existing statistics
tables and plain ADD-only payload excluding bookkeeping. Version bounds/order and
SHA-384 widths remain explicit. The SQLx constructor identifies the captured
fixed engine/connection/configuration profile; it is not a version-string alias.

Validation: `timeout 60s lake build` passed all 16 jobs, including rejection of
dirty metadata, payload bookkeeping edits and CREATE under the transaction mode.
These are reusable data/predicate interfaces only. They are not yet wired into
the VC, gate or runner outcomes; those remain required before a profile proof can
be accepted. Frontend implementation can now compile the generated records.

## Checked runner relation and profile-bound gate

`RunnerFootprint.lean` models exact metadata insertion (including version,
description, checksum, TRUE, timestamp, elapsed value and existing rows), allowing
native rowid allocation and enumeration. Statistics maintenance changes only rows
of the two named statistics tables and preserves every definition and other table.
`RunnerExecution.lean` distinguishes rollback, payload failure, committed success,
timing/cache errors after commit, and conservative commit-error observations.
Elapsed time uses SQLx's actual signed i64 cast, not an assumed nonnegative range.
The arbitrary-storage preservation theorem retains every table outside the named
bookkeeping/statistics footprint, with no new axioms.

`VerificationConditions` now has a final profile parameter with the legacy
profile as default, an explicit readiness obligation, and universal coverage of
`ProfileExecutes`. Legacy of_run helpers and complete example theorems still pass.
`ProofChecker.lean` reconstructs the target with sealed `Generated.profile`;
`compile.EXPECTED_SOURCE` includes the same argument. The frontend must emit this
constant before the combined public CLI integration can pass.

Validation: `timeout 60s lake build` passed 18 jobs; the trusted checker built with
`nix develop --command timeout 120s lake build migration-proof-checker`; the actual
bounded kernel-gate suite passed under Nix. It accepts honest legacy proofs and
checked refutations and rejects the existing attacks, protected-profile mutation,
and an old autocommit proof hidden behind a candidate alias when the sealed input
selects SQLx. Metadata success/committed-error trace witnesses and the full Atuin
VC remain required; totality alone intentionally permits a safe rollback outcome.
