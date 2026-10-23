"""Each mutant of the query, number, key, alias, UPSERT, algorithm, query-without-FROM, JSON,
JSON function, `json_each`, clock, date function, date modifier, subquery, expression form,
DISTINCT and HAVING, foreign key, trigger, possible result, parameter and compound mutant tables changes the verdict
of an authored case.

ADR 0012 requires that the conformance suite tests each rule of query semantics and
resolution, and its slices add the number, write, join and key rules: a changed copy of the
model that no case notices shows a missing case. The cases are the authored cases of the
`conformance.authored_*` module of each table, recorded natively with their outputs. The mutants
of writes, joins and table forms are in `tests/conformance_table_mutants_test.py`, a separate Nix
suite, so that each suite stays within its time limit on a hosted runner. Each test is one
measurement of at most 16 mutants, which builds one base copy for its mutants (`measure_set`)
and then the mutant copies in parallel. The two Nix suites of mutants run at the same time on a
hosted runner, which slows each test about twice. The number and query-without-FROM mutants (17)
were one measurement until it took 176 seconds alone on eight cores (October 2026) and more than
its limit of 300 seconds beside the other suite, as the base copy and most of these mutant copies
build almost every module. As three measurements, of the 6 mutants of arithmetic, the other 7
number mutants and the 4 mutants of queries without FROM, each took at most 124 seconds alone. Every case must agree with the base copy. Each mutant copy then classifies the case
that the mutant names as its target, which keeps the elaboration of case terms short.
"""

from pathlib import Path

import pytest

from conformance import (algorithm_mutants, alias_mutants, authored_algorithms, authored_aliases, authored_clock,
                         authored_date_functions, authored_date_modifiers, authored_fromless, authored_json,
                         authored_json_each, authored_json_functions, authored_keys, authored_numbers,
                         authored_queries, authored_upserts, clock_mutants, date_function_mutants,
                         date_modifier_mutants, fromless_mutants, json_each_mutants, json_function_mutants,
                         json_mutants, upsert_mutants, authored_subqueries, subquery_mutants,
                         authored_expression_forms, expression_form_mutants, authored_distinct_having,
                         distinct_having_mutants, authored_foreign_keys, foreign_key_mutants,
                         authored_triggers, trigger_mutants, authored_possible_results, possible_result_mutants,
                         authored_parameters, parameter_mutants, authored_compound, compound_mutants,
                         authored_pragmas, pragma_mutants)
from conformance import key_mutants, number_mutants, query_mutants
from tests.mutant_sets import Mutants, Targets, measure_set

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_lean,
              pytest.mark.requires_native("translation-program", "sqlite3")]

def test_every_query_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored query cases notice every changed rule of query semantics
    (`conformance.query_mutants`), so these rules are tested."""
    measure_set(runtime_root, [authored_queries], [(query_mutants.MUTANTS, query_mutants.TARGETS)])


def number_mutant_table(arithmetic: bool) -> tuple[Mutants, Targets]:
    """The number mutants of `conformance.number_mutants` in `Arithmetic.lean`, or the others,
    with their targets: two measurements, each within the time limit."""
    mutants = {name: mutant for name, mutant in number_mutants.MUTANTS.items()
               if (mutant[0] == number_mutants.ARITHMETIC) == arithmetic}
    return mutants, {name: number_mutants.TARGETS[name] for name in mutants}


def test_every_arithmetic_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored number cases notice every changed rule of arithmetic and `CAST` to INTEGER
    (the mutants of `conformance.number_mutants` in `Arithmetic.lean`)."""
    measure_set(runtime_root, [authored_numbers], [number_mutant_table(True)])


def test_every_other_number_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored number cases notice every changed rule of sums and averages, number text,
    and `coalesce` (the other mutants of `conformance.number_mutants`)."""
    measure_set(runtime_root, [authored_numbers], [number_mutant_table(False)])


def test_every_fromless_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored query-without-FROM cases notice every changed rule of queries without FROM
    (`conformance.fromless_mutants`)."""
    measure_set(runtime_root, [authored_fromless], [(fromless_mutants.MUTANTS, fromless_mutants.TARGETS)])


def test_every_json_function_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored JSON and JSON function cases notice every changed rule of the JSON functions
    (`conformance.json_mutants`, `conformance.json_function_mutants`)."""
    measure_set(runtime_root, [authored_json, authored_json_functions],
                [(json_mutants.MUTANTS, json_mutants.TARGETS),
                 (json_function_mutants.MUTANTS, json_function_mutants.TARGETS)])


def test_every_json_each_and_clock_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored `json_each` and clock cases notice every changed rule of `json_each` and the
    clock (`conformance.json_each_mutants`, `conformance.clock_mutants`)."""
    measure_set(runtime_root, [authored_json_each, authored_clock],
                [(json_each_mutants.MUTANTS, json_each_mutants.TARGETS),
                 (clock_mutants.MUTANTS, clock_mutants.TARGETS)])


def test_every_date_function_and_modifier_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored date and time function and modifier cases notice every changed rule of
    the date and time functions and their modifiers (`conformance.date_function_mutants`,
    `conformance.date_modifier_mutants`), so these rules are tested."""
    measure_set(runtime_root, [authored_date_functions, authored_date_modifiers],
                [(date_function_mutants.MUTANTS, date_function_mutants.TARGETS),
                 (date_modifier_mutants.MUTANTS, date_modifier_mutants.TARGETS)])


def test_every_key_and_alias_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored key and rowid alias cases notice every changed rule of unique key values and
    rowid aliases (`conformance.key_mutants`, `conformance.alias_mutants`)."""
    measure_set(runtime_root, [authored_keys, authored_aliases],
                [(key_mutants.MUTANTS, key_mutants.TARGETS), (alias_mutants.MUTANTS, alias_mutants.TARGETS)])


def test_every_upsert_and_algorithm_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored UPSERT and conflict algorithm cases notice every changed rule of conflict
    handling (`conformance.upsert_mutants`, `conformance.algorithm_mutants`)."""
    measure_set(runtime_root, [authored_upserts, authored_algorithms],
                [(upsert_mutants.MUTANTS, upsert_mutants.TARGETS),
                 (algorithm_mutants.MUTANTS, algorithm_mutants.TARGETS)])


def test_every_subquery_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored subquery cases notice every changed rule of subqueries
    (`conformance.subquery_mutants`): `NOT IN` that ignores a NULL, a correlated reference that
    does not read the outer row, a scalar subquery that gives its last row, and a name that
    resolves outward first (ADR 0018, slice 1)."""
    measure_set(runtime_root, [authored_subqueries], [(subquery_mutants.MUTANTS, subquery_mutants.TARGETS)])


def test_every_expression_form_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored cases of the expression forms notice every changed rule
    (`conformance.expression_form_mutants`): an `IN` list under a right column's collation,
    `BETWEEN` that gives NULL before it checks for false, `CASE` whose NULL base matches a NULL
    `WHEN`, and `||` that skips a NULL operand (ADR 0018, slice 2)."""
    measure_set(runtime_root, [authored_expression_forms],
                [(expression_form_mutants.MUTANTS, expression_form_mutants.TARGETS)])


def test_every_distinct_having_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored cases of DISTINCT, HAVING and aggregates inside expressions notice every
    changed rule (`conformance.distinct_having_mutants`): `HAVING` that keeps a NULL group, an
    aggregate over the first row of its group only, and `DISTINCT` that keeps every NULL row
    (ADR 0018, slice 3)."""
    measure_set(runtime_root, [authored_distinct_having],
                [(distinct_having_mutants.MUTANTS, distinct_having_mutants.TARGETS)])


def test_every_foreign_key_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored cases of enforced foreign keys (ADR 0018, slice 4) notice every changed
    rule (`conformance.foreign_key_mutants`): a check of a composite child key with one NULL
    column, `SET NULL` that deletes the child row, `CASCADE` on update that keeps the old child
    key, and a lookup that compares the child value without the parent key's affinity."""
    measure_set(runtime_root, [authored_foreign_keys], [(foreign_key_mutants.MUTANTS, foreign_key_mutants.TARGETS)])


def test_every_trigger_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored cases of triggers (ADR 0018, slice 5) notice every changed rule
    (`conformance.trigger_mutants`): triggers that run oldest first, `WHEN` that a NULL passes,
    `RAISE(IGNORE)` in an `AFTER` trigger that still runs the later triggers of the row, `UPDATE OF`
    that runs for every `UPDATE`, and a trigger that fires itself."""
    measure_set(runtime_root, [authored_triggers], [(trigger_mutants.MUTANTS, trigger_mutants.TARGETS)])


def test_every_possible_result_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored cases of the results that SQLite may give (ADR 0018, slice 6) notice every
    changed rule (`conformance.possible_result_mutants`): a list that ignores `OFFSET`, a list with
    only the choice of `Query.results`, a list that cuts a group with one row too many, and groups
    that `DESC` does not reverse."""
    measure_set(runtime_root, [authored_possible_results],
                [(possible_result_mutants.MUTANTS, possible_result_mutants.TARGETS)])


def test_every_parameter_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored cases of parameters (ADR 0019, slice 1) notice every changed rule of the model
    (`conformance.parameter_mutants`): a parameter with an affinity, `ORDER BY ?` as a column
    number, and a `LIMIT ?` that accepts a real with a fraction."""
    measure_set(runtime_root, [authored_parameters], [(parameter_mutants.MUTANTS, parameter_mutants.TARGETS)])


def test_every_compound_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored cases of compound SELECT (ADR 0019, slice 3) notice every changed rule of the
    model (`conformance.compound_mutants`): operators that group from the right, `EXCEPT` with
    duplicates, NULL unequal to NULL, the compound collation from the right-most term or always
    `BINARY`, `IN` with the compound collation, the right term of `EXCEPT` run after empty left
    rows, and an `ORDER BY` term sorted under `BINARY`."""
    measure_set(runtime_root, [authored_compound], [(compound_mutants.MUTANTS, compound_mutants.TARGETS)])


def test_every_pragma_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored cases of pragmas (ADR 0019, slice 2) notice every changed rule of the model
    (`conformance.pragma_mutants`): `fkid` in declaration order, `foreign_key_check` that skips a
    missing parent table, `table_info` with the `cid` of every column, and REPLACE deletes that
    fire no trigger with recursive triggers on."""
    measure_set(runtime_root, [authored_pragmas], [(pragma_mutants.MUTANTS, pragma_mutants.TARGETS)])
