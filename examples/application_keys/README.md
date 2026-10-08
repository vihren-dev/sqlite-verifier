# Application-key invoice example

This variant verifies the same column addition and audit-table creation as
`add_column_then_table`. It selects amount as a logical key for this small
engineering example and admits only distinct, non-NULL keys. It does not claim
that invoice amounts are business identifiers or that the SQL declares UNIQUE.
A real application can select its own identifier and protected fields.

Use `projectedInterpretation` and equality when physical rowids and stored row
order are part of the requirement. Use `applicationKeyInterpretation` and
`applicationKeyPreservation` when key tuples identify records and their order
does not matter. The latter compares complete records with `List.Perm`: it
retains multiplicity and rejects lost, added or changed records. Its read refuses
NULL or duplicate logical keys rather than merging them. Key identity uses exact
tagged values; SQLite affinity and collation comparisons require their own meaning.

The general `Interpretation` and `LogicalContract` constructors remain available
for another identity, NULL, duplicate or ordering policy. This example supports
the existing schema extension; it adds no INSERT SELECT, DROP, RENAME or table
rebuild support.

From the repository root, use profile 3.51.0:

```sh
migration-check verify --profile 3.51.0 \
  --schema examples/application_keys/approved/schema.sql \
  --requirements examples/application_keys/approved/Requirements.lean \
  --interpretation examples/application_keys/approved/Interpretation.lean \
  --migration examples/application_keys/add_column_then_table/migration.sql \
  --next-interpretation examples/application_keys/add_column_then_table/NextInterpretation.lean \
  --proofs examples/application_keys/add_column_then_table/Proofs.lean
```

`Interpretation.current` uses the sealed starting-schema translation. The proof
reuses the complete library certificate and generic observation-preservation
laws; it assumes no particular stored rows. The starting witness is the empty
invoice table. The generated target binds the current source files and runtime.
