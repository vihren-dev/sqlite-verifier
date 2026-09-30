# ADR 0003 P3: construct generated SQL inputs in the bundle checker

Created 2026-09-30. Status: DONE.
Status file: [status](20260930-adr3-p3-generated-inputs.status.md).
Spec: [ADR 0003](../docs/adr-0003-agent-proof-preparation.md) P3 row and assumption A5;
shared encoding: [conformance format v1](../docs/conformance-format-v1.md) (ADR 0004).
Base: `adr3/data-path` stacked on `adr4/model-conformance`.

## Observable behavior when done

- `verify-bundle` no longer starts a Lean process to compile `SqlInputs.lean`. It
  passes the frontend's result to `migration-bundle-checker` as a versioned
  structural JSON record (profile, starting schema, next schema, script), and the
  checker constructs `Generated.nextSchema`, `Generated.script` and
  `Generated.profile` as kernel-checked declarations itself.
- The structural encoding and its Lean decoder are the ones ADR 0004 uses: one
  Python encoder and one Lean codec module, shared by the production checker and
  the conformance runner. The production SQL library does not import `Lean`.
- The checker rejects a record whose starting schema differs from the compiled
  `Generated.startSchema`, an unsupported version, or malformed data.
- A bundle prepared for different SQL is still rejected. Exported copies of the
  three generated declarations are accepted only when definitionally equal to the
  constructed ones.
- `verify`, `prepare`, statuses, exit codes and reported input hashes are
  unchanged. SQL admission and validation still run in the frontend.

## Tests

- Parity (ADR assumption A5): for the shipped examples, literal-write scripts
  covering every statement constructor and value kind, and ADR 0004's authored
  cases, the constructed declarations have the same type as, and values
  definitionally equal to, today's compiled `SqlInputs`. (Reducibility hints are
  not compared: they depend on how a literal is written, such as
  `nextSchema := startSchema`, and do not affect what the kernel accepts. The
  recorded corpora are upstream tests the frontend mostly rejects, so they are not
  a parity source.)
- Negative: a record with a changed starting schema, another version, or malformed
  JSON is rejected.
- The existing bundle suite (status parity, invalid proofs, altered contract, wrong
  SQL, shared file, SQL-edit reuse) and installed acceptance pass unchanged.
- Measured `verify-bundle` time before and after on the small and Atuin examples.

## Tricky points

- Elaborated literals and constructed terms differ structurally (numerals, negative
  integers, bytes, `nextSchema := startSchema`), so comparison must be definitional.
- Replay always uses the verifier's declarations; the comparison of exported copies
  is a guard against mismatched preparation, not the soundness argument.
- The approved contract still compiles against the compiled `SchemaInputs`.
- `VerifierConformance` is a test-only library; the shared codec must be buildable
  in the production Lean runtime without it.
- `conformance/case_format.py` has many importers; keep its names working.
