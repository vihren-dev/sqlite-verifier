# Reusable engineering examples

The invoice examples below are synthetic engineering examples, not real-pilot acceptance evidence.
The source-backed [Atuin example](atuin/README.md) demonstrates the primary
preservation contract: the resulting schema still represents the same old business
histories, without prescribing new fields or verifying framework bookkeeping.
Its [acceptance review](../docs/atuin-pilot-review.md) records owner approval,
agent-executed checks and the limits of the available productivity evidence.
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
Each case folder has a `belay.toml` that names these inputs, its profile and its
approval baseline. It is the project configuration file of the command line
tool; the tool does not read it yet, and the tests use it to find each case. Its
`[test]` table holds the status that the tests expect.
The verifier generates sealed `SchemaInputs.lean`, `SqlInputs.lean` and
`Generated.lean`; these are not user inputs. The approved interpretation imports
only `SchemaInputs` from these modules and uses `Generated.profile` and
`Generated.startCatalog`. Its protected baseline pins `schema.sql` and the
complete approved Lean closure. Approved modules cannot import the migration,
the resulting catalog or candidate sources.

The public proof implementations are
`packages/sqlite-verifier/SqliteVerifier/Demonstration.lean` and
`packages/sqlite-verifier/SqliteVerifier/ReverseDemonstration.lean`. The named projection, coverage,
schema-update, and verification primitives remain available for adapting the
requirements or writing a different proof.

`allowed_failure` is a separate policy example with its own `approved/` files.
It permits precisely SQLite's table-exists prepare error at zero-based statement
position 2. Resolution continues after that error, so the resulting catalog
contains the unreached table; the failure representation reads the catalog of the
committed prefix.
Both earlier changes remain committed, the fourth statement is skipped, and the
failed outcome reads the same protected invoice projection from resulting storage.
This demonstrates the general failure contract; it does not weaken or replace
the successful-applicability requirements shared by the other three examples.
Its separate protected baseline also pins the source schema and generated-schema
interpretation. For candidates that use `examples/approved`, supply its
`baseline.json` with `--approved-baseline`, including a checked refutation.
Supply `examples/allowed_failure/approved/baseline.json` for `allowed_failure`.

The [application-key variant](application_keys/README.md) uses complete records
without physical rowids and compares them with permutation. Its logical key
policy requires defined, distinct, non-NULL keys. This separate engineering
example explains how to choose the flexible interpretation and contract helpers.

The [constant-default example](constant_default/README.md) adds a required
priority with default 7 and preserves every invoice rowid and amount. It has
its own contract and proofs project. Supply
`examples/constant_default/approved/baseline.json` with `--approved-baseline`.
