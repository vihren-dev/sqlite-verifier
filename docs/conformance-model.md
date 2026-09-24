# Concrete native/model comparisons

Build the production parser and Lean library, then run inside the pinned Nix shell:

```
python3 tests/conformance_model_test.py
python3 conformance/model_check.py "$(command -v sqlite3)" ./build/sqlite-parser
```

The five cases are explicitly project-derived examples in `model_cases.py`.
They do not replace, simplify, or change the imported upstream fixture and its
expected values. Each case declares initial native rows, candidate SQL, expected
resulting tables/cells, and expected error independently of model evaluation.

The actual SQL passes through the production parser, `starting_schema`,
`statements`, and `sql_inputs`. Generated Lean definitions therefore denote the
same SQL submitted to the native engine. Kernel-checked equalities compare model
results against the independent expected schema, rowids, cells, and error
positions/categories. Assertions use `decide +kernel`; no SQL axioms or native
proof oracle are introduced. A negative test replaces the expected invoice rows
with an empty target and confirms Lean rejects that equality.

| Derived case | Required independent observation |
| --- | --- |
| ADD then CREATE | All three old rowids and integer/text/NULL cells survive; appended cells are NULL; audit table is empty. |
| ADD then conflicting CREATE | ADD remains committed; later table creation is not reached. |
| CREATE then duplicate-column ADD | New audit table remains committed; old invoices remain unchanged. |
| CREATE then missing-table ADD | New audit table remains committed; missing-table error occurs at statement 1. |
| ADD at 2000 columns with a duplicate name | Column-limit error takes precedence over duplicate-column error; all columns and empty contents remain. |

All row observations use explicit `ORDER BY rowid`. Equal application values at
distinct rowids test multiplicity/identity; UTF-8 text and a preexisting NULL are
included. The empty 2000-column case uses an exact count plus complete column
metadata, since selecting rowid plus 2000 fields would itself exceed SQLite's
result-column limit. SQLite's native diagnostic names its temporary
`sqlite_altertab_full` object; the modeled error records the original table name
`full` with the same error category.

The native runner uses a new temporary database, disables startup rc scripts,
executes statements in order with stop-on-first-error, and reopens the database
to inspect committed prefixes. It checks exact version/source ID, DQS=0 and
MAX_COLUMN=2000. Native operations time out after 5s, parsing after 5s, and each
Lean check after 30s. `SQLITE3` can explicitly select the pinned executable.

Reports label these results `KERNEL_CHECKED_CONCRETE_ASSERTIONS` and
`PRODUCTION_PIPELINE`, separately from native observations. The coverage is all
**five authored cases**, not all possible inputs or all SQLite behavior. It does
not establish universal native refinement, arbitrary application-query
preservation, or pilot acceptance. The separately proved universal preservation
and complete interpretation-contract example remain distinct evidence.

Imported `alter3` observations remain `NOT_YET_MODEL_CHECKED`: their inherited
view dependency is unsupported by the current semantic subset. Their original
expectations and import denominator are unchanged.
