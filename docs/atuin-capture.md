# Atuin history migration capture

This is a real SQLx 0.9.0 migration-runner capture of Atuin revision
`5b10eb09c664d316b7384210399b02e6127f4027`, not an invocation of the Atuin
executable and not yet a verification result. Original migration bytes are in
`conformance/atuin_capture/migrations`. All 162 resolved registry packages match
the versions and checksums in that revision's Cargo.lock. The capture uses the
declared Nix environment's rustc 1.98.1 and Cargo 1.98.0; upstream requests
rustc 1.98.0. `provenance.json` records source and migration hashes.

Run from the repository root:

```sh
nix develop .#capture
export CARGO_HOME="$PWD/build/atuin-cargo-home"
export CARGO_TARGET_DIR="$PWD/build/atuin-cargo-target"
timeout 600 cargo build --locked --manifest-path conformance/atuin_capture/Cargo.toml
timeout 40 python3 tests/atuin_capture_test.py
```

For a new raw capture, supply a nonexistent database path and the migration
directory to `build/atuin-cargo-target/debug/atuin-sqlx-capture`. The runner first
uses SQLx's `run_to(20260224000100)`, closes the pool (including actual
optimize-on-close), reads the persisted baseline, then reopens with Atuin's
options and uses `run()` with the same immutable catalog. It records the
invocation result and another read-only snapshot after closing. This reproduces migration
execution without compiling unrelated application subsystems. It uses Atuin's
WAL, NORMAL synchronization, foreign-keys-on, 4 MiB journal limit, regexp,
optimize-on-close and default pool settings. It clears cached statements after
each successful migration invocation, as Atuin does. It omits Atuin's background
WAL compactor and informational task; no concurrent application activity is
claimed or simulated.

`capture.json` contains every `sqlite_schema` row, including three implicit
indexes with NULL SQL and the engine-managed `sqlite_stat1`/`sqlite_stat4` tables,
plus all six/seven bookkeeping rows, statistics rows and effective native
configuration/runtime limits. All four schema inventories contain ten objects.
`before.sql` and `after.sql` serialize every non-NULL table/index
definition; implicit indexes are recreated by their exact PK/UNIQUE declarations.
Root pages, timestamps and execution durations are captured observations, not
logical migration promises. The engine is the actual bundled SQLite 3.46.0,
source `96c92aba00c8375bc32fafcdf12429c58bd8aabfcadab6683e35bbb9cdebf19e`.
It is not the verifier's original 3.51.0 profile.
The statistics definitions are captured input, not a claim that ordinary user
CREATE TABLE may create reserved SQLite names. An earlier capture before closing
contained eight objects; that incomplete persisted baseline is superseded by this
close-and-reopen capture. Statistics maintenance is distinct from preserving
application history storage.

SQLx ensures `_sqlx_migrations`, rejects dirty entries, reads applied versions
and checksums, and rejects applied versions absent from the catalog. It compares
checksums as it iterates the catalog. SQLite-specific migrator locking is a no-op.
For each pending ordinary migration it begins a transaction, executes the SQL,
inserts the successful bookkeeping row with SHA-384 of the original SQL and
`execution_time=-1`, then commits. It updates elapsed nanoseconds afterward,
outside the transaction. That UPDATE can fail after the payload has committed.
Atuin's later connection acquisition/cache clearing can also fail after commit.
Existing-version matches skip execution; a schema alone does not establish
that the selected migration is pending. Rollback and post-commit failures must
therefore remain distinct in any proposed invocation certificate.

Primary sources: [Atuin Cargo.lock](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/Cargo.lock),
[Atuin builder](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-common/src/db/sqlite/builder.rs),
[Atuin migration wrapper](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-common/src/db/mod.rs),
[SQLx SQLite migration implementation](https://docs.rs/crate/sqlx-sqlite/0.9.0/source/src/migrate.rs).
The downloaded crate archives were checked against the original lock checksums.
Compile-option comparison excludes only `COMPILER=` while recording its actual
value separately. Bundled SQLite's `sqlite3.c` lines 21969–21975 construct this
entry from compiler version macros; it identifies the build tool. Every other
compile option and every captured runtime limit remains an exact match.

## Native adversarial outcomes

After the same locked build, run
`timeout 45 python3 -m unittest discover -s tests -p 'atuin_*test.py'` inside the
capture shell. Eight native scenarios have receipts in
`conformance/atuin_capture/runner-receipts.json`; the test regenerates them under
`build/`. These are native observations, not model proofs.

- Successful migration adds NULL shell values and one checksum-bound metadata row.
- A statement failure after ADD rolls back the entire payload and metadata.
- An injected metadata INSERT failure rolls back the successful ADD.
- An injected timing UPDATE failure occurs after commit: shell exists and the
  successful metadata row retains execution_time=-1.
- Dirty metadata, an incorrect prior checksum and an unknown applied version each
  reject before changing state.
- An already-applied matching target is a successful no-op.

Fault triggers deliberately perturb the experiment's schema; they are not part
of the pilot baseline and do not enlarge the admitted schema subset. The payload
failure appends a failing statement to a temporary copy, retaining original
fixtures. Exact pre/post schema and metadata equality is checked for rollback
and preflight failure. Committed outcomes preserve existing metadata and every
non-history schema object. New metadata checksums are compared to original bytes.

All scenarios retain a native-valid three-row witness with two NULL TEXT primary
keys, signed 64-bit minimum/maximum physical rowids, TEXT/REAL/BLOB in INTEGER
affinity columns, repeated command values, numeric TEXT-affinity conversions,
embedded-NUL TEXT and non-UTF8 BLOB. Observations compare each old value's storage
class, quoted representation and complete byte representation, plus rowid.
`PRAGMA integrity_check` returns `ok`. This is finite conformance evidence, not
an exhaustive valid-state characterization. Cache clearing succeeds in these
runs; its possible failure after commit is identified from source only and is
not represented as an injected or empirically observed failure.
The tests also read history after pool closure and require preservation of every
old stored value. They retain the full statistics-table schema and record whether
optimization changed statistics rows, without requiring those rows unchanged.
