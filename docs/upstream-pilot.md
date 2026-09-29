# Runtime upstream pilot (W6)

`just conformance-upstream` builds the pinned 3.51.0 Tcl testfixture and runs the
real upstream harness through execution traces. Tcl expands loops, substitutions
and capability guards. The source ZIP digest and every selected file digest are
in [corpus-v1/manifest.json](../conformance/corpus-v1/manifest.json).
The ZIP lacks Fossil's generated `manifest.tags`; the test-only derivation restores
release metadata. SQLite still verifies all source hashes, and acquisition checks
the exact release source ID.

The 2026-09-29 pilot executed 12 of 20 `alter*.test` files successfully, observing
1,012 runtime assertions and recording 177 cases (at most 20 per file). Eight
files require fault-injection, corruption, authorizer or query-plan contexts.
Every executed assertion has an outcome or exclusion reason in the manifest.
The loop-expanded `altercol` assertions are included. Two independent extractions
produced the same case digest.

Fresh C-API execution must reproduce each captured successful Tcl result list,
and error outcome/text, including the setup prefix. Tcl's untyped formatting is
only an extraction check. REAL/BLOB result formatting, callbacks, multiple
connections, file/configuration operations, TEMP/ATTACH state, unreadable objects
and setup ending in a transaction have explicit exclusions. Views, triggers,
constraints and WITHOUT ROWID tables otherwise remain in the typed native corpus.
Native-only deletion removes redundant prefix commands while preserving the exact
initial observation and full trace; trials are bounded to 32 per case. Original
prefixes and minimization counts remain in each record.

`just conformance-corpus` checks fresh native replay and derives structural input
again with today's production frontend. The initial [progress report](../reports/20260929-adr4-upstream-progress.json)
is **2 AGREE, 175 MODEL_UNSUPPORTED, 0 DISAGREE, 0 HARNESS_ERROR**. No unsupported
case counts as agreement. File-level requirement references are provenance only;
they are not attributed to every case. Untagged cases remain explicitly untagged.

The frozen version is immutable evidence. Refreshes write under `build/`; a
reviewed change to its cases requires a new corpus version and denominator.
The bounded replay check runs in `just test`; rebuilding the upstream Tcl pilot
is a separate target. This replaces static extraction for new mining, while the
three original static fixtures remain historical regression evidence.
