# Reusable engineering examples

The invoice examples below are synthetic engineering examples, not real-pilot acceptance evidence.
The source-backed [Atuin example](atuin/README.md) demonstrates the primary
preservation contract: the resulting schema still represents the same old business
histories, without prescribing new fields or verifying framework bookkeeping.
The first three candidates use the exact same files in `approved/`: a current schema,
logical requirements, and current interpretation. No database contents are given.
The proofs quantify every admitted set of invoice rows, identities, and amounts.

- `add_column_then_table` adds nullable `invoices.note`, then creates `audit`.
- `table_then_column` reverses those statements and independently proves the
  same approved requirements. Its theorem proves the run equivalence.
- `missing_required_column` creates only `audit`. Its checked negative theorem
  refutes the unchanged requirement that `invoices.note` exist. A rejected proof
  alone would not establish this violation.

The logical projection includes every physical rowid and designated amount. It
preserves duplicate amounts and does not claim application query ordering or
`SELECT *` compatibility. The examples require successful execution under the
fixed autocommit profile; they do not assume whole-file rollback or crash safety.

For each candidate provide `approved/Requirements.lean`, `approved/schema.sql`,
`approved/Interpretation.lean`, and that candidate's `migration.sql`,
`NextInterpretation.lean`, and `Proofs.lean`, with profile `3.51.0`.
The verifier generates `SqlInputs.lean` and `Generated.lean`; these are not user
inputs. Approved modules import no generated or candidate module.

The public proof implementations are `SqliteVerifier/Demonstration.lean` and
`SqliteVerifier/ReverseDemonstration.lean`. The named projection, coverage,
schema-update, and verification primitives remain available for adapting the
requirements or writing a different proof.

`allowed_failure` is a separate policy example with its own `approved/` files.
It permits precisely a table-exists error at zero-based statement position 2.
Both earlier changes remain committed, the fourth statement is skipped, and the
failed outcome reads the same protected invoice projection from resulting storage.
This demonstrates the general failure contract; it does not weaken or replace
the successful-applicability requirements shared by the other three examples.
