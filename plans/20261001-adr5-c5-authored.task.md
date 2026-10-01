# ADR 0005 C5: neutral authored cases

Created 2026-10-01. Status: DONE.
Status: [progress](20261001-adr5-c5-authored.status.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md), sections 1.3,
3.1, 3.3 and 3.6.

## Observable outcomes

The authored inputs cover the ADR's schema, statement, function and value
categories against neutral tables. Cases exercise typed parameters and storage
classes, integer limits, NULL and empty values, empty and single-row tables,
schema changes, triggers, foreign-key cascades, constraint failures, transaction
sequences, UPSERT, aggregates, joins, casts, REAL arithmetic, ordered ties and
window boundaries, DISTINCT, and controlled clock and JSON functions.

Every case records statement outputs and an established execution profile.
The existing 29 requirement scenarios can also be recorded with this evidence;
their legacy recording path and frozen v1–v3 artifacts remain unchanged.
Requirement tags identify a demonstrated scenario, not complete satisfaction of
the requirement. JSON retains feature metadata without invented requirement IDs.

A retained report binds the old corpus, requirement inventory, authored inputs
and native evidence by digest. It shows before and after case counts for all
3,500 inventory rows, including zero-case rows. The inventory includes features
outside the ADR's SQL scope; zero rows remain visible without a claim that C5
covers those features. The report distinguishes evidence growth from model
support. The final corpus membership is frozen by C6.

## Behavioral verification

All authored records replay on fresh native connections with identical typed
outputs, snapshots, profiles and clocks, and remain below the case size limit.
Tests check concrete output rows, shape, direct counts and transaction effects;
in particular, failed statements keep prior transaction writes while rolling
back the failing statement, and trigger/cascade effects exceed direct counts.
Ordering evidence includes both distinct and shared boundary groups. Clock reads
in defaults and triggers use the supplied values. Invalid comparison evidence
and writing probes remain covered by C0's existing positive and rejecting tests.

Requirement counts resolve each tag unambiguously and count one case once per
row even if both short and full IDs occur. Before/after reports use the same
inventory denominator. Unsupported authored behavior remains MODEL_UNSUPPORTED.
Focused native and compiled classification checks, the hermetic model suite,
and document checks pass with configured timeouts.

## Tricky points and sources

Reuse `native_record.record_sql`, `execution_profile.measured_profile`,
`corpus.native_replay`, and the SQL boundary examples in the existing ordering,
clock and profile tests. `requirement_cases.py` holds legacy scenarios;
`requirements-3.51.0.json` is the fixed requirement inventory. SQLite supplies
all recorded outcomes; tests assert observable facts without editing them.
Parameters must include an entry for every reached statement. A constraint
error ends acquisition, so independent failures require separate cases.
`BEGIN` mode must match the selected profile. Limited writes with unspecified
selection remain exclusions. No real workload SQL, names or results enter the
core, and C5 does not extend production SQL semantics.

## Completion evidence

The [retained report](../reports/20261001-adr5-c5-authored.md) binds all 43
authored records and the fixed inventory. All native replays pass. Requirement
rows with a case increase from 60 to 98 of 3,500, with no lost rows. Focused
checks: 22 passed. Full pinned hermetic model suite: 132 passed in 201.98 seconds.
Final document checks: 2 passed. Independent contract audit found no remaining
actionable findings. Frozen corpus membership remains unchanged until C6.
