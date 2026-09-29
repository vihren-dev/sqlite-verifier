# General conformance laws

ADR 0004 W5 is implemented in `VerifierConformance/Laws.lean`, outside the
production library. `rollback` proves that BEGIN, a transaction-free successful
body, and ROLLBACK restore the initial database. `SuccessfulBody` records success
of each production literal/DDL transition and excludes transaction controls.

`statement_atomicity` covers every halt of production `advance`: visible data
is unchanged and committed data is the saved snapshot (or the visible database
outside a transaction). `add_column_shape` states the exact successful ADD table:
row count and rowids are preserved and each values list gains exactly one NULL.
These last two laws hold even without a SupportedSql premise, so in particular
hold on the admitted subset. No native refinement is inferred.

The kernel/axiom and native property witnesses run in `tests/conformance_laws_test.py`
as part of the Nix model suite. Native witnesses cover empty and populated tables,
transactional writes, a failing unique constraint, ADD, and rollback.
