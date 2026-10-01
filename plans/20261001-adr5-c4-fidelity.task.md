# ADR 0005 C4: upstream fidelity causes

Created 2026-10-01. Status: IN PROGRESS.
Status: [progress](20261001-adr5-c4-fidelity.status.md).
Spec: [ADR 0005 §3.6](../docs/adr-0005-conformance-corpus-scale.md#36-fidelity-triage-authored-cases-and-mutants).

## Observable outcomes

Every historical candidate excluded because its Tcl and fresh native execution
differ has a named, evidence-backed cause. The ledger binds the frozen extraction
and identifies each file, assertion and occurrence; it covers all 143 such
candidates, including the ADR's 123 prefix-result differences and the 20 other
result/error differences. Historical evidence and native records remain unchanged.

Mechanical capture errors are fixed at their shared source. SQLite's unique
Tcl method abbreviations have the same capture semantics as their full names;
helpers keep their own result semantics and callback registrations remain excluded.
Untraced BLOB operations, testfixture-only features and database-path observations
have named causes and cannot be mistaken for a disagreement in SQL semantics.
Reopen and SQL-call boundaries preserve the native behavior they represent.

## Behavioral verification

The ledger's file/id/occurrence keys match every differing-result candidate in
the frozen extraction, without omissions or duplicates. Pinned real Tcl tests
exercise abbreviated helpers, callback registration and lifecycle operations,
including rejecting callback/BLOB contexts and recovery after reset. Native
observations are never edited to match Tcl. Focused native/Tcl fidelity checks and
the existing corpus regressions pass with configured subprocess/suite timeouts.

## Tricky points and sources

`upstream_proxy.tcl` traces native connection methods. The pinned engine's
`src/tclsqlite.c` resolves unique prefixes through `Tcl_GetIndexFromObj`.
`upstream_assertions.py` accumulates exclusions and reset-scoped prefixes;
`upstream_fidelity.py` compares actual results and minimizes native evidence.
Frozen `corpus-v3/extraction.json.gz` is the historical denominator. Its first
error check precedes row checks, so a candidate may have several symptoms; retain
the cause of its actual historical refusal. Paths in `PRAGMA database_list` are
environment observations, not values to normalize. Testfixture callback/module
behavior must not be copied into the independent native oracle.
