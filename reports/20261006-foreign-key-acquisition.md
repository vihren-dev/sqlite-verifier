# Foreign-key acquisition recovery

The pinned SQLite 3.51.0 `e_fkey.test` acquisition records 514 of 940 assertions
after setup restoration is supported, compared with 2 before the change.
All 514 admissions passed the pilot's Tcl-result checks and fresh native replay.
The [machine-readable report](20261006-foreign-key-acquisition-yield.json)
retains every assertion's disposition, source and extractor hashes, complete
profile, and case archive identities.

This is acquisition coverage. Production FK semantics and frozen corpus v1–v5
remain unchanged. The fixed profile still refuses an actual setting change
during a case and requires setup to end outside a transaction.

## Paired admission evidence

The source generates 500 mutations with Tcl `rand()`. The two full runs use the
same pinned source and profile but have different expanded SQL. Their case
archives retain the SQL that actually ran; their bytes are bound by digest.

A separate paired check applies the old authorizer to the exact original setup
commands and migration SQL of all 514 after-run admissions. It admits 2 and
refuses 512 because of an FK-setting write. The two old admissions reproduce the
new observations exactly. Each paired input has its own SQL/profile digest.
The 426 remaining refusals below are source-bound independent-run counts; they
are outside this paired comparison.

## Remaining refusals

| Count | Reason and boundary |
| ---: | --- |
| 128 | Supplementary helpers require a read-only SELECT; this run encounters unsupported helper SQL in the assertion or retained prefix. |
| 183 | SQL or connection callbacks lack a retained replay context. |
| 1 | An application function combines with a callback context. |
| 88 | Application functions, callbacks and nested SQL combine. |
| 18 | Those contexts also include an external `sqlite3_limit` change. |
| 2 | The preceding combination has no SQL observation. |
| 3 | `e_fkey-6.2`, `6.3` and `6.4` start inside a transaction left open by their setup. |
| 1 | `e_fkey-5.3` actually changes FK ON to OFF during the recorded assertion. |
| 2 | `e_fkey-4.1` and `5.1` expect the SQLite default OFF setting, while the declared source profile opens with FK ON. Their original expectations remain unchanged. |

The two Tcl expectation failures also explain runtime exit 1 in both full
captures. Both captures reach the completion marker and expose 940 assertions.
The report does not count failed expectations as native evidence.

## Reset correction and checks

A failed `reset_db` can leave partial effects. A successful reset can run
optional `SETUP_SQL` before it returns. The capture now retains named refusals
for both contexts instead of assuming an empty database. A later plain
successful reset clears those refusals. Tests use the real pinned Tcl harness
and verify the refusal, recovery and fresh replay.

The full acquisition receipt belongs to commit `9390c778`. The later reset
correction does not affect this source: it has no failed reset or `SETUP_SQL`.
A separate diagnostic wrapper initializes Tcl with `srand(1)` before running
each proxy against the unchanged source. Both proxies produce byte-identical
event streams: 5,432,796 bytes, SHA256
`080d3368c06bbf3d348d6e91bfd40bed99316275a90632b524315801f3538753`.
The seed belongs only to this diagnostic; acquisition policy is unchanged.

The final sandboxed upstream suite passes 63 tests with no skips. JUnit evidence
is `/nix/store/ra19ap3r7afqkw6ahhq74mr4id28gb0c-sqlite-verifier-test-upstream-1/junit.xml`.
The native profile, recorder, context, fidelity and clock subset passes 32 tests.

## Reproduction and retained artifacts

The full runs call `conformance.upstream_pilot.pilot` with the Nix-pinned
`conformanceNative.fixture` and `conformanceNative.upstream`, `limit=None`,
`patterns=("e_fkey.test",)` and `catalog_profile_policy=True`. Each outer command
has a 1200-second limit; the Tcl child has the pilot's 60-second limit.
The unchanged baseline used `ef2cc19e`; the after run used `9390c778`.

Manifests, archives and logs remain in `build/fk-acquisition-before` and
`build/fk-acquisition-after` in the task workspace. The after archive is
3,596,232 bytes, with SHA256
`f51ed1471feb79628d06172eecb76e6eda60df3f6d476c5218bcbb9c133c132e`.
The uncompressed record payload SHA256 is
`2915b872afb9c659cc117087add1bb9c2b8259dbd880f7dda4045901e81b8bff`.
Reset diagnostic events and receipts remain in `build/fk-reset-equivalence`.
