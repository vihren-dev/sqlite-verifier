"""Each mutant of the query, number, key, write, row-write, DELETE, join, alias, UPSERT,
algorithm, query-without-FROM, JSON, JSON function, `json_each`, clock, date function and date
modifier mutant tables changes the verdict of an authored case.

ADR 0012 requires that the conformance suite tests each rule of query semantics and
resolution, and its slices add the number, write, join and key rules: a changed copy of the
model that no case notices shows a missing case. The cases are the authored cases of
`conformance.authored_queries`, `authored_numbers`, `authored_keys`, `authored_writes`,
`authored_row_writes`, `authored_deletes`, `authored_joins`, `authored_using`,
`authored_right`, `authored_merged`, `authored_aliases`, `authored_upserts`,
`authored_algorithms`, `authored_fromless`, `authored_json`, `authored_json_functions`,
`authored_json_each`, `authored_clock`, `authored_date_functions` and
`authored_date_modifiers`, recorded natively with their outputs. Five measurements, one for
queries and numbers, one for JSON and the clock, one for the date and time functions and
their modifiers, one for writes and joins, and one for keys, rowid
aliases, UPSERT and conflict algorithms, each build one base copy for their mutants, which
keeps each test within its time limit on a hosted runner; every case must agree with the
base copy. Each mutant copy then classifies the case that the mutant names as its target,
which keeps the elaboration of case terms short.
"""

from pathlib import Path
from types import ModuleType

import pytest

from conformance import (algorithm_mutants, alias_mutants, authored_algorithms, authored_aliases, authored_clock,
                         authored_date_functions, authored_date_modifiers, authored_deletes, authored_fromless,
                         authored_joins, authored_json, authored_json_each, authored_json_functions, authored_keys,
                         authored_merged, authored_numbers, authored_queries, authored_right, authored_row_writes,
                         authored_upserts, authored_using, authored_writes, clock_mutants, date_function_mutants,
                         date_modifier_mutants, fromless_mutants, json_each_mutants, json_function_mutants,
                         json_mutants, upsert_mutants)
from conformance.native_replay import prepare
from conformance import (delete_mutants, join_mutants, key_mutants, merged_mutants, number_mutants, query_mutants,
                         right_mutants, row_write_mutants, using_mutants, write_mutants)
from conformance.record_parser import runtime_library
from conformance.resolve_mutants import measure

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_lean,
              pytest.mark.requires_native("parser-library", "sqlite3")]
ROOT = Path(__file__).resolve().parents[1]


Mutants = dict[str, tuple[str, str, str]]
"""A mutant table: the file, the exact text and the replacement of each mutant."""
Targets = dict[str, tuple[str, ...]]
"""The target cases of each mutant."""


def measure_set(runtime_root: Path, modules: list[ModuleType], tables: list[tuple[Mutants, Targets]]) -> None:
    """Every target case of the mutant tables, recorded natively from the case modules, agrees
    with the unchanged model, and every mutant changes the verdict of its target case. Only the
    target cases are recorded and classified: the coverage test kernel-checks every case."""
    mutants: Mutants = {}
    targets: Targets = {}
    for table, table_targets in tables:
        assert not set(table) & set(mutants), "mutant names must be unique"
        mutants |= table
        targets |= table_targets
    wanted = {name for names in targets.values() for name in names}
    library = runtime_library(runtime_root)
    cases = []
    for module in modules:
        for record in module.records([case for case in module.definitions() if case.name in wanted]):
            case, answer = prepare(record, library)
            assert case is not None, (record["name"], answer)
            cases.append(case)
    result = measure(cases, ROOT, runtime_root, mutants, targets)
    assert set(result) == set(mutants)
    survivors = [name for name, item in result.items() if not item["killed"]]
    assert not survivors, f"mutants that no case notices (add a case for each): {survivors}"


def test_every_query_and_number_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored query, number and query-without-FROM cases notice every changed rule of
    query semantics and numbers (`conformance.query_mutants`, `conformance.number_mutants`,
    `conformance.fromless_mutants`), so these rules are tested."""
    measure_set(runtime_root, [authored_queries, authored_numbers, authored_fromless],
                [(query_mutants.MUTANTS, query_mutants.TARGETS), (number_mutants.MUTANTS, number_mutants.TARGETS),
                 (fromless_mutants.MUTANTS, fromless_mutants.TARGETS)])


def test_every_json_and_clock_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored JSON, JSON function, `json_each` and clock cases notice every changed rule
    of the JSON functions and the clock (`conformance.json_mutants`,
    `conformance.json_function_mutants`, `conformance.json_each_mutants`,
    `conformance.clock_mutants`), so these rules are tested. The JSON mutants have their
    own measurement: with the query mutants, the measurement took 265 s of its 300 s limit
    on a hosted runner, and went over it once."""
    measure_set(runtime_root, [authored_json, authored_json_functions, authored_json_each, authored_clock],
                [(json_mutants.MUTANTS, json_mutants.TARGETS),
                 (json_function_mutants.MUTANTS, json_function_mutants.TARGETS),
                 (json_each_mutants.MUTANTS, json_each_mutants.TARGETS),
                 (clock_mutants.MUTANTS, clock_mutants.TARGETS)])


def test_every_date_function_and_modifier_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored date and time function and modifier cases notice every changed rule of
    the date and time functions and their modifiers (`conformance.date_function_mutants`,
    `conformance.date_modifier_mutants`), so these rules are tested. They have their own
    measurement, so that the JSON and clock measurement stays within its time limit."""
    measure_set(runtime_root, [authored_date_functions, authored_date_modifiers],
                [(date_function_mutants.MUTANTS, date_function_mutants.TARGETS),
                 (date_modifier_mutants.MUTANTS, date_modifier_mutants.TARGETS)])


def test_every_key_alias_upsert_and_algorithm_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored key, rowid alias, UPSERT and conflict algorithm cases notice every changed
    rule of unique key values, rowid aliases and conflict handling (`conformance.key_mutants`,
    `conformance.alias_mutants`, `conformance.upsert_mutants`, `conformance.algorithm_mutants`),
    so these rules are tested."""
    measure_set(runtime_root, [authored_keys, authored_aliases, authored_upserts, authored_algorithms],
                [(key_mutants.MUTANTS, key_mutants.TARGETS), (alias_mutants.MUTANTS, alias_mutants.TARGETS),
                 (upsert_mutants.MUTANTS, upsert_mutants.TARGETS),
                 (algorithm_mutants.MUTANTS, algorithm_mutants.TARGETS)])


def test_every_write_and_join_mutant_changes_a_verdict(runtime_root: Path) -> None:
    """The authored write and join cases notice every changed rule of writes with output, of
    row-dependent writes, of DELETE and of joins (`conformance.write_mutants`,
    `conformance.row_write_mutants`, `conformance.delete_mutants`, `conformance.join_mutants`,
    `conformance.using_mutants`, `conformance.right_mutants`, `conformance.merged_mutants`), so
    these rules are tested."""
    measure_set(runtime_root, [authored_writes, authored_row_writes, authored_deletes, authored_joins, authored_using,
                               authored_right, authored_merged],
                [(write_mutants.MUTANTS, write_mutants.TARGETS), (row_write_mutants.MUTANTS, row_write_mutants.TARGETS),
                 (delete_mutants.MUTANTS, delete_mutants.TARGETS), (join_mutants.MUTANTS, join_mutants.TARGETS),
                 (using_mutants.MUTANTS, using_mutants.TARGETS), (right_mutants.MUTANTS, right_mutants.TARGETS),
                 (merged_mutants.MUTANTS, merged_mutants.TARGETS)])
