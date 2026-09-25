# Bounded coverage report

After building both parsers and the Lean library, run inside the pinned
`nix develop path:./nix` environment:

```sh
python3 conformance/coverage_report.py --output build/coverage.json
```

`SQLITE3` may select the exact pinned 3.51.0 engine. Shared `just coverage` and CI
use this command; the JSON is a check artifact, not a proof certificate. Each
subprocess has a timeout. The command refreshes the existing evidence and exits
nonzero if any check fails. A failed or unavailable comparison has unknown
counts (`null`), never zero discrepancies. Diagnostics retain the failing command.
The collector runs the complete native and model test wrappers once, including
vendored-source/fixture checks and the rejected false-empty model assertion.
Their freshly returned JSON feeds this report directly. The aggregate test recipe
does not repeat those comparisons or parser regressions. Existing report files
are never reused as evidence; standalone coverage performs the same fresh checks.
`just coverage` prepares those prerequisites. The Atuin check executes ordinary
SQL through the pinned SQLite CLI; it has no application or framework dependency.
The top-level native/model profile remains 3.51.0. The `additional_grammars`
entry separately reports 3.46.0 syntax evidence; it does not transfer the 3.51.0
native/model observations to the older engine. Both grammar inventories and
their own smoke-test counts must be available for a passing report.

The report keeps these scopes separate:

| Scope | Denominator and limitation |
| --- | --- |
| Model proofs | Six explicitly named theorem/axiom probes after a library build; not all library declarations and not a replacement for the independent product gate. |
| Grammar inventory | Generated and upstream default-grammar production counts; equal counts are not parser equivalence. Production execution coverage is not instrumented. |
| Parser regressions | Twenty authored smoke scripts per release, plus separate malformed/limit/span and release-distinction checks; not a percentage of productions. |
| Documented claims | Five traceability entries: three upstream requirement IDs and two version-matched snapshot anchors. The total SQLite documentation claim count is unknown. Runtime-limit lowering is reference-only and excluded by the fixed profile. |
| Imported fixtures | Three selected assertion instances of 59 textual alter3.test call sites; two distinct IDs of 55. Not runtime-expanded Tcl cases or the whole SQLite corpus. The inherited view is retained, so model checking remains unsupported. |
| Semantic support | Named restricted statement forms, including explicit transactions and literal writes, as defined in semantic-subset.md; this inventory is not a coverage denominator. |
| Native/model observations | All five authored derived cases compared against independent expected results through the production parser/translator and Lean checks. Zero discrepancies means only those completed comparisons. |
| Atuin SQL (`atuin_sql`, SQLite 3.46.0) | Six independent native SQL cases: empty/singleton/three-row histories, negative metadata rowids and NULL keys, maximum-rowid allocation, and statement ABORT followed by explicit ROLLBACK. These are SQL-mechanics tests, not framework traces or witnesses of the example's approved assumptions. |

The fresh Atuin wrapper output must have the complete case identities, source SQL
hashes, expected schema count and native-only status labels. Missing, duplicated,
failed or altered observations leave comparison counts unknown. It runs once per
aggregate check and writes `build/atuin-sql.json` for inspection; an old file is
never substituted for its current output. One case deliberately exercises SQLite's
random rowid-allocation boundary outside the deterministic model's admitted domain.
`model_status` remains `NOT_COMPARED_BY_THIS_TEST`: these observations are not
presented as native/model refinement proofs. Public CLI and kernel checks separately
establish whether the supplied example proof is accepted.

`conformance/coverage_catalog.py` links documentation claims to definitions,
lemmas, and fixtures without treating a citation as a proof. Detailed native
observations and named theorem axiom output are embedded in the report. Failures
may indicate resource/tool problems or mismatches; a failed check alone is not a
witness of violated requirements. The CLI's `VERIFIED`/`VIOLATED` outcomes remain
separate from this report's evidence-check status.

No corpus completion, universal native refinement, schema-text/physical-layout
proof, application-query guarantee, real-pilot acceptance, or owner approval
follows from this report. Existing fixture and model-comparison documentation
remains authoritative about provenance and exclusions.
