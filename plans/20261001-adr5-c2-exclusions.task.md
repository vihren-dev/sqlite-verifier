# ADR 0005 C2: narrow upstream extraction exclusions

Created 2026-10-01. Status: IN PROGRESS.
Status: [progress](20261001-adr5-c2-exclusions.status.md).
Spec: [ADR 0005 §3.4](../docs/adr-0005-conformance-corpus-scale.md#34-narrow-exclusions-before-adding-volume).

## Observable outcomes

Upstream helper reads become ordinary native statement evidence when their Tcl
semantics can be reproduced faithfully: onecolumn returns the first column of
the first row, exists reports existence, and eval row scripts must have no side
effects. Unreproduced helper semantics and scripts with side effects remain named
exclusions. Native evidence is never edited to agree with Tcl expectations.

Attached-database and second-connection exclusions last while those contexts
are open. After they close, eligibility returns only with a prefix proven
replayable on a fresh database or a reconstructed state verified against the
traced execution. Reads through a second connection cannot be silently replayed
on the primary connection. Nondeterministic-function exclusions follow the
candidate's SQL and prefix, not an unrelated earlier test. Supported controlled
clock profiles handle clock reads. Unsupported settings are counted per setting.

Candidates retain every applicable exclusion reason. Cap/sample labels are
additional reasons and never replace fidelity/context failures. A before/after
yield table for e_createtable.test, e_update.test, alter.test and e_expr.test
accounts for runtime assertions, recorded cases and exclusions. Frozen corpus
membership is unchanged by this package; expanded acquisition feeds later gates.

## Behavioral verification

Pinned Tcl/native end-to-end tests cover onecolumn and exists, pure eval row
scripts and rejected side effects, ATTACH/DETACH and second-connection lifetimes,
faithful recovery and refusal of a false recovery after uncommitted reads,
candidate-scoped nondeterminism, unsupported settings, and multiple retained
reasons after a cap. Existing native/Tcl fidelity and frozen replay regressions
remain green. Yield measurements use pinned sources and record extraction
configuration; tests and subprocesses have explicit timeouts.

## Tricky points and sources

`upstream_proxy.tcl` captures real runtime events; Tcl expands loops and branches.
`upstream_pilot.assertions` currently accumulates reset-scoped exclusions and
captures SQL prefixes; pilot selection overwrites earlier reasons.
`upstream_fidelity.py` compares Tcl result shapes and minimizes verified prefixes.
`native_record.py` remains the independent observation authority. Trace primary
and auxiliary connection observations separately; closing a handle does not
prove that replaying its earlier reads on the primary was faithful. Helper SQL
can contain multiple statements or an error and must retain actual Tcl helper
semantics. Reuse verified native prefixes rather than inventing another SQL
interpreter. Profiles and statement outputs from C0/C1 must remain compatible.
