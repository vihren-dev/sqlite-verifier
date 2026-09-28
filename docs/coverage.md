# Conformance test scope

`just test` runs the source checks through pytest and independently cached Nix
test targets. There is no aggregate `coverage.json` or extra evidence gate.
A pytest failure fails its host invocation or Nix derivation.

The native/model target runs the pinned SQLite 3.51.0 engine, production parser
and translator, and Lean kernel assertions. The kernel target tests independent
proof replay. Their dependencies determine Nix cache invalidation. Other tests,
including production host containment and Atuin CLI examples, execute freshly.
See [test targets](../build-support/README.md) for direct and cached commands.

Passing tests support only their declared scenarios, not a percentage of all
SQLite behavior. These scopes remain distinct:

| Scope | Denominator and limitation |
| --- | --- |
| Model proofs | Six explicitly named theorem/axiom probes after a library build; not all library declarations and not a replacement for the independent product gate. |
| Grammar inventory | Generated and upstream default-grammar production counts; equal counts are not parser equivalence. Production execution coverage is not instrumented. |
| Parser regressions | Twenty authored smoke scripts per release, plus separate malformed/limit/span and release-distinction checks; not a percentage of productions. |
| Documented claims | Five traceability entries: three upstream requirement IDs and two version-matched snapshot anchors. The total SQLite documentation claim count is unknown. Runtime-limit lowering is reference-only and excluded by the fixed profile. |
| Imported fixtures | Three selected assertion instances of 59 textual alter3.test call sites; two distinct IDs of 55. Not runtime-expanded Tcl cases or the whole SQLite corpus. The inherited view is retained, so model checking remains unsupported. |
| Semantic support | Named restricted statement forms, including explicit transactions and literal writes, as defined in semantic-subset.md; this inventory is not a coverage denominator. |
| Native/model observations | All five authored derived cases compared against independent expected results through the production parser/translator and Lean checks. Zero discrepancies means only those completed comparisons. |
| Atuin SQL (`atuin_sql`, SQLite 3.46.0) | Three independent native SQL cases: empty, singleton and three-row histories. Each checks preservation of all old stored fields under the supplied payload. These are bounded storage observations, not framework traces or witnesses of the example's approved assumptions. |

Atuin SQL tests use SQLite 3.46.0 and preserve old stored classes/bytes under the
supplied SQL. They do not establish a universal native/model refinement proof or
application-query guarantee. Model comparisons use SQLite 3.51.0; syntax tests for
3.46.0 do not transfer model evidence to that version.

`conformance/coverage_catalog.py` retains the documented claim/theorem inventory.
Named theorem tests check their allowed axiom sets. Pytest reports and command
artifacts retain diagnostics without revalidating successful reports in Python.
No corpus completeness or owner approval follows from a passing test run.
