"""Each mutant of the write, row-write, DELETE, join, index, `WITHOUT ROWID`, collation, CHECK,
generated-column, `STRICT`, DROP and after-error mutant tables changes the verdict of an authored
case.

These measurements were in `tests/conformance_query_mutants_test.py`. The Nix suite of that
file went over its limit of 1200 seconds on a hosted runner (pull request #191), so they have
their own suite, `tableMutants`. The cases are the authored cases of
`conformance.authored_writes`, `authored_row_writes`, `authored_deletes`, `authored_joins`,
`authored_using`, `authored_right`, `authored_merged`, `authored_indexes`,
`authored_without_rowid`, `authored_collations`, `authored_checks`, `authored_generated`,
`authored_strict`, `authored_drops` and `authored_after_error`, recorded natively with their
outputs. Each test builds one base copy for its mutants with `measure_set`, and each mutant copy classifies the
case that the mutant names as its target. The writes and the joins are separate measurements of
at most 22 mutants, so that each test stays far within its limit of 300 seconds while the
other Nix suite of mutants runs at the same time.
"""

from pathlib import Path

import pytest

from conformance import (after_error_mutants, authored_after_error, authored_checks, authored_collations,
                         authored_deletes, authored_drops, authored_generated,
                         authored_indexes, authored_joins, authored_merged, authored_right, authored_row_writes,
                         authored_strict, authored_using, authored_without_rowid, authored_writes, check_mutants,
                         collation_mutants, delete_mutants, drop_mutants, generated_mutants, index_mutants,
                         join_mutants, merged_mutants, right_mutants, row_write_mutants, strict_mutants,
                         using_mutants, without_rowid_mutants, write_mutants)
from tests.mutant_sets import measure_set

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_lean,
              pytest.mark.requires_native("translation-program", "sqlite3")]


def test_every_index_and_without_rowid_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored index and `WITHOUT ROWID` cases notice every changed rule of index forms
    (`conformance.index_mutants`: a filter that is ignored, an expression key read as a
    column, and a CREATE INDEX that runs without its uniqueness check) and of `WITHOUT ROWID`
    tables (`conformance.without_rowid_mutants`: a scan in insertion order, and a key column
    that admits NULL), ADR 0014, slices 1 and 2."""
    measure_set(runtime_root, [authored_indexes, authored_without_rowid],
                [(index_mutants.MUTANTS, index_mutants.TARGETS),
                 (without_rowid_mutants.MUTANTS, without_rowid_mutants.TARGETS)])


def test_every_collation_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored collation cases notice every changed rule of collations
    (`conformance.collation_mutants`): a comparison that ignores the collation, the right
    operand's collation chosen first, and a key that compares with BINARY (ADR 0014, slice 3)."""
    measure_set(runtime_root, [authored_collations], [(collation_mutants.MUTANTS, collation_mutants.TARGETS)])


def test_every_check_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored CHECK cases notice every changed rule of CHECK constraints
    (`conformance.check_mutants`): a CHECK that NULL fails, CHECK after the unique keys,
    REPLACE that skips the row, and a write that skips the CHECK (ADR 0014, slice 4)."""
    measure_set(runtime_root, [authored_checks], [(check_mutants.MUTANTS, check_mutants.TARGETS)])


def test_every_generated_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored generated-column cases notice every changed rule of generated columns
    (`conformance.generated_mutants`): an UPDATE that does not recompute a generated value,
    the `hidden` value of a VIRTUAL column for a STORED one, and an INSERT without a column
    list that expects a value for each generated column (ADR 0014, slice 5)."""
    measure_set(runtime_root, [authored_generated], [(generated_mutants.MUTANTS, generated_mutants.TARGETS)])


def test_every_strict_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored `STRICT` cases notice every changed rule of `STRICT` tables
    (`conformance.strict_mutants`): a type check that NULL fails, `ANY` with the affinity of
    its declared type, and an `OR IGNORE` that skips a row with a type error (ADR 0014,
    slice 6)."""
    measure_set(runtime_root, [authored_strict], [(strict_mutants.MUTANTS, strict_mutants.TARGETS)])


def test_every_drop_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored DROP cases notice every changed rule of DROP INDEX and DROP TABLE
    (`conformance.drop_mutants`): a DROP TABLE that keeps the table's indexes, a DROP that
    does not move the later positions, and `IF EXISTS` that still reports `no such table`
    (ADR 0014, slice 7)."""
    measure_set(runtime_root, [authored_drops], [(drop_mutants.MUTANTS, drop_mutants.TARGETS)])


def test_every_write_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored write cases notice every changed rule of writes with output, of
    row-dependent writes and of DELETE (`conformance.write_mutants`,
    `conformance.row_write_mutants`, `conformance.delete_mutants`), so these rules are tested."""
    measure_set(runtime_root, [authored_writes, authored_row_writes, authored_deletes],
                [(write_mutants.MUTANTS, write_mutants.TARGETS), (row_write_mutants.MUTANTS, row_write_mutants.TARGETS),
                 (delete_mutants.MUTANTS, delete_mutants.TARGETS)])


def test_every_join_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored join cases notice every changed rule of joins (`conformance.join_mutants`,
    `conformance.using_mutants`, `conformance.right_mutants`, `conformance.merged_mutants`), so
    these rules are tested."""
    measure_set(runtime_root, [authored_joins, authored_using, authored_right, authored_merged],
                [(join_mutants.MUTANTS, join_mutants.TARGETS), (using_mutants.MUTANTS, using_mutants.TARGETS),
                 (right_mutants.MUTANTS, right_mutants.TARGETS), (merged_mutants.MUTANTS, merged_mutants.TARGETS)])


def test_every_after_error_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored cases of the statements after an error notice every changed rule of the run
    that continues (`conformance.after_error_mutants`): an error that closes the transaction, an
    `OR ROLLBACK` that keeps it open, and a failed statement that changes the catalog."""
    measure_set(runtime_root, [authored_after_error], [(after_error_mutants.MUTANTS, after_error_mutants.TARGETS)])
