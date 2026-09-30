# Runtime upstream pilot

Created 2026-09-29. Status: DONE.
Spec: [ADR 0004](../docs/adr-0004-model-conformance-validation.md).

## Required outcomes

Execute the pinned 3.51.0 alter*/altertab* Tcl test pilot through a logging sqlite3 proxy; retain SQL plus fresh typed native traces, runtime-expanded test identity and provenance. Report per-file yield and explicit reasons for excluded multi-connection, file-level, user-function, fault-injection and query-plan cases. Tcl expectations confirm extraction, not typed model truth.

## Observable validation

A live pinned pilot reports exact file/case denominators and exclusions; loop-generated assertions are captured; captured cases replay natively; archive identity and determinism are checked.

## Constraints and relevant code

Existing static import remains historical evidence. Use real Tcl execution, not regex extraction of dynamic tests; unsupported model cases remain in a frozen corpus.

Work stays in the dedicated adr4 workspace. No merge to main or adr3 rebase before user approval.
