# Pinned native fixture slice

Run `python3 tests/conformance_native_test.py` with SQLite 3.51.0 from the Nix
environment on PATH, after building the production parser. `SQLITE3` may point
to that exact executable. Every subprocess has a timeout; the longest is 12s.
To inspect the separate evidence report:

```
python3 conformance/native_fixture.py "$(command -v sqlite3)" ./build/sqlite-parser
```

## Imported evidence

`conformance/upstream/alter3.test` is an unchanged file from the pinned SQLite
source archive. The bounded extractor retains three ordered assertion instances:
`alter3-3.1` occurrence 1, `alter3-3.1` occurrence 2, and `alter3-3.2` occurrence 1.
It preserves exact SQL, raw expected Tcl strings, and original source locations.
Duplicate test names do not overwrite each other. The second `3.1` sets
`schema_version=10`; its empty expectation is a real assertion.

The selected expectations use only integers and empty Tcl list elements. The
importer rejects other assertion shapes rather than pretending to implement Tcl.
Comparison follows `execsql` flat row/cell order: NULL becomes the empty string.
Typed native JSON observations are retained separately, so this original Tcl
convention does not discard the NULL distinction from the evidence report.

The source contains **59 textual assertion call sites, 55 distinct textual IDs**.
This import covers **3 call instances, 2 distinct IDs**. These are source-text
counts, not a count of runtime-expanded Tcl cases or the entire upstream corpus.
Conditional branches, loops, raw-file checks, API tests, and other cases remain
unimported. The original expected results do not come from the formal model.

## Configuration and inherited state

The runner uses one native connection and preserves `LEGACY_FILE_FORMAT=1`.
It recreates the selected slice's relevant prior SQL state from unchanged SQL in
`alter3-2.1`, `2.4`, `2.5`, and `2.99`. Those prerequisite actions are not claimed
as four additional imported assertions. Earlier operations on subsequently dropped
tables and failing statements are not replayed; full-file Tcl execution and
identical on-disk layout are not claimed.

Crucially, `alter3-2.5` leaves view `v1` after `2.99` drops table `t1`. The slice
recreates `t1` and keeps the view. The runner retains that dependency. The current
formal subset excludes existing views, so this original fixture cannot silently
be marked model-checked by deleting `v1`.

The SQLite shell differs from a default C-API connection: it enables defensive
mode and disables trusted-schema mode. The runner explicitly sets defensive OFF
and trusted-schema ON to reproduce the Tcl test connection. Without the former,
SQLite silently ignores the source's schema-version assignment; the final-state
regression detects that difference. Startup rc files are disabled. Column limit
is explicitly set to 2000. Engine version, source ID, MAX_COLUMN=2000, and DQS=0
are checked against the pinned build.

The report distinguishes `MATCHES_UPSTREAM`, `PARSED`,
`NOT_YET_TRANSLATED`, and `NOT_YET_MODEL_CHECKED`. It records final rowids/cells,
schema text including `v1`, schema version 11, and native compile options.
Production parsing currently covers each selected SQL block; production semantic
translation and Lean assertions remain unwired. No universal native-refinement
or schema-completeness claim follows from these observations.

## Version-matched requirement traceability

Published HTML strips requirement markers. The unchanged version-matched
`e_createtable.test` retains upstream evidence IDs; matching published text is
vendored alongside it. These references do not imply that the entirety of
`e_createtable.test` was imported or checked.

| Upstream ID or exact snapshot anchor | Claim and current evidence |
| --- | --- |
| R-42316-09582; `e_createtable.test:854` | An omitted DEFAULT means NULL; `lang_createtable.html` DEFAULT clause and the selected ADD fixture expose NULL observations. |
| R-25473-20557; `e_createtable.test:1059` | Column count is bounded by SQLITE_MAX_COLUMN; native compile settings and explicit runtime limit are recorded. |
| R-27775-64721; `e_createtable.test:1074` | Relevant limits can be lowered at runtime; the runner fixes the column limit explicitly. |
| `lang_altertable.html#alter_table_add_column` | ADD appends columns; unrestricted additions do not rewrite stored table content. No upstream requirement ID for these specific sentences was located in this bounded import. |
| `limits.html#max_column` | The documented default column maximum is 2000; checked against the selected engine. |

Source, amalgamation, and documentation archive URLs/hashes are recorded in
`parser/upstream/README.md`; each retained fixture/document file is bound by
`conformance/upstream/sha256.json`. Original public-domain notices are retained.
