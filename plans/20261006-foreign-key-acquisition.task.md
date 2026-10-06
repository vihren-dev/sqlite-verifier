# Foreign-key acquisition recovery

Status: IN PROGRESS. Created 2026-10-06.

## Outcome

Later assertions in the pinned SQLite `e_fkey.test` become recordable when
their original setup reconstructs the required database and execution profile.
Foreign-key setting changes in that setup do not permanently exclude later
assertions after the source restores the required setting. Acquisition checks
the real setting and transaction state at the assertion boundary. It never
inserts a reset, changes source SQL or expectations, or discards a required
database dependency.

A `foreign_keys` write inside an open transaction keeps SQLite's no-op
behavior. Actual setting changes during the recorded assertion remain outside
the fixed-profile case format. Unknown contexts, unclosed setup transactions,
and setup that does not restore the selected profile retain named refusals.
A successful source `reset_db` is distinct from restoration in the same
database. A failed reset leaves a named refusal because it can have partial
side effects. A reset initializer whose SQL is not retained also stays refused;
a later plain successful reset can restore eligibility. Existing frozen
v1–v5 evidence and production FK semantics stay intact.

Source: [issue #34](https://github.com/vihren-dev/sqlite-verifier/issues/34).
Specification: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md),
[execution profiles](../docs/execution-profile.md).

## Acceptance

Real pinned Tcl tests cover FK OFF, recovery after a real reset, both directions
of transaction-local no-op writes, restoration without reset, and data created
while enforcement is OFF that remains necessary after restoration. Acquired
records preserve original SQL and expectations, check the captured prefix
results, and match fresh native replay. Tests prove that unrestored settings
and open setup transactions remain excluded and that ordinary case SQL cannot
change its profile.

A bounded before/after acquisition of the same pinned `e_fkey.test` records
source and extractor identities, assertion counts, admitted case identities,
and a reason for every remaining refusal. New evidence is separate from the
frozen corpora. The relevant native profile, context, fidelity and upstream
suites pass with configured timeouts. Independent review and its resolutions
remain in the append-only review log.

## Constraints and relevant code

`native_acquisition.open_case` owns authorizer refusals. `native_record.record_sql`
establishes the profile before setup and reads it back at the case boundary and
after statements; readback must not repair a changed setting. The source's
setup SQL is the evidence for temporary FK changes. `upstream_proxy.tcl` and
`upstream_assertions.iter_assertions` preserve real reset boundaries and ordered
prefixes. `upstream_fidelity.check_results` checks captured Tcl outcomes before
prefix minimization; minimization must preserve required data and retain the
original commands. Profile routing stays explicit. No new execution-profile
or corpus wire format is required for recovery after restoration.
