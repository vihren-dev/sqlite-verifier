# Conformance test scope

`just test` runs the source checks through pytest and independently cached Nix
test targets. Versioned conformance progress and measured coverage are documented in
[conformance-progress.md](conformance-progress.md); they do not authorize product proofs.
A pytest failure fails its host invocation or Nix derivation.
The development conformance tier checks all frozen authored and synthetic cases
plus a stable upstream sample. `just test-full`, CI and packaging retain the
complete model, kernel, generation and historical evidence checks.

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
| Historical documented claims | Five traceability entries: three upstream requirement IDs and two version-matched snapshot anchors. The total SQLite documentation claim count is unknown. Runtime-limit lowering is reference-only and excluded by the fixed profile. |
| Historical imported fixtures | Three selected assertion instances of 59 textual alter3.test call sites; two distinct IDs of 55. Not runtime-expanded Tcl cases or the whole SQLite corpus. The inherited view is retained, so model checking remains unsupported. |
| Frozen corpus | V1: 177 runtime-extracted cases; V2: those same records plus six authored requirement cases. V2 baseline: 8 AGREE, 175 MODEL_UNSUPPORTED; see conformance-progress.md. |
| Measured execution | 36/41 scoped model match arms; 6,003/16,272 native branch arcs in reached functions on 93 admitted cases. Source-bound reports list exclusions. |
| Semantic support | Named restricted statement forms, including explicit transactions and literal writes, as defined in semantic-subset.md; this inventory is not a coverage denominator. |
| Native/model observations | All five authored derived cases retain independent expected results and now run through persistent native observation, compiled `classifyCase` and kernel `checkCase` proofs. Focused transaction, storage, admission, transport and mutation regressions are listed in conformance-model.md. Generated runs and frozen corpus counts are reported separately; no universal refinement claim. |

Model comparisons use SQLite 3.51.0; syntax tests for 3.46.0 do not transfer
model evidence to that version. The former native Atuin SQL cases only observed
SQLite's own ADD COLUMN behavior and were removed on 2026-09-29.

`conformance/coverage_catalog.py` retains the documented claim/theorem inventory.
Named theorem tests check their allowed axiom sets. Pytest's own output and JUnit
XML carry diagnostics; there are no separate per-case receipts.
No corpus completeness or owner approval follows from a passing test run.
