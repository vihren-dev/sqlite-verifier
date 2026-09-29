# Translator-independent native recording

Created 2026-09-29. Status: DONE.
Spec: [ADR 0004](../docs/adr-0004-model-conformance-validation.md).

## Required outcomes

Versioned native records retain SQL, schema metadata, typed rows and statement outcomes even for views, triggers, constraints and WITHOUT ROWID tables. Replay derives structural model inputs afresh with the current frontend. Admitted cases retain the independent metadata cross-check. Native recording never needs translator admission.

## Observable validation

Live SQLite tests retain out-of-subset objects, row identities and transaction snapshots; replay reports unsupported without losing native records; existing admitted cases retain verdicts.

## Constraints and relevant code

conformance/native_connection.py, native_trace.py, native_metadata.py; wide rows require chunking and WITHOUT ROWID identity comes from primary-key metadata. Preserve errors separately from model verdicts.

Work stays in the dedicated adr4 workspace. No merge to main or adr3 rebase before user approval.
