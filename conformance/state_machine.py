"""Bounded Hypothesis stateful generation in well-scoped and error-seeking modes."""

from collections import Counter
from pathlib import Path

from hypothesis import settings, seed, strategies as st
from hypothesis.stateful import RuleBasedStateMachine, rule, run_state_machine_as_test

from conformance.case_format import Json
from conformance.generated_program import Program, command, native_laws
from conformance.model_check import acquire, compiled
from migration_check.sql_values import SqlValue

VALUES = st.sampled_from([None, "", "1", " 1", "1.0", "a'\nb", b"", b"\x00\xff", -(2**63), 2**63-1])


def generate(runtime: Path, *, error_seeking: bool, examples: int = 20, steps: int = 8,
             fixed_seed: int = 4004) -> tuple[dict[str, int], list[dict[str, Json]]]:
    """Hypothesis shrinks failed executions; fixed seeds and bounded settings make CI repeatable."""
    counts: Counter[str] = Counter()
    records: list[dict[str, Json]] = []

    class Machine(RuleBasedStateMachine):
        """Each action appends constructors; state chooses fresh table and key names."""
        def __init__(self) -> None:
            super().__init__()
            self.program = Program()
            self.ddl = Program(schema="CREATE TABLE exists_table(v BLOB);", rows={})
            self.serial = 1

        @rule(value=VALUES)
        def write(self, value: SqlValue) -> None:
            """Use a fresh unique key, then update it with the same literal domain."""
            self.serial += 1
            self.program.commands += [command("insert", "t", key=self.serial, value=value),
                                      command("update", "t", key=self.serial, value=value)]

        @rule(rollback=st.booleans(), value=VALUES)
        def transaction(self, rollback: bool, value: SqlValue) -> None:
            """Exercise explicit commit/rollback around a successful body."""
            self.serial += 1
            self.program.commands += [command("beginTransaction"),
                command("insert", "t", key=self.serial, value=value),
                command("rollback" if rollback else "commit")]

        @rule()
        def schema_change(self) -> None:
            """Fresh auxiliary tables permit ADD without changing the DML fixture shape."""
            self.serial += 1
            name = f"a{self.serial}"
            self.ddl.commands += [command("createTable", name), command("addColumn", name, column="extra")]

        @rule(error=st.sampled_from(["duplicate-table", "missing-table", "duplicate-column", "commit", "rollback", "begin", "unique", "not-null"]))
        def error(self, error: str) -> None:
            """Error mode admits ordinary SQL failures; well-scoped mode keeps making writes."""
            if not error_seeking:
                self.write(None)
                return
            if error == "duplicate-table":
                self.ddl.commands.append(command("createTable", "exists_table"))
                return
            options = {
                "duplicate-table": [command("createTable", "t")],
                "missing-table": [command("addColumn", "absent")],
                "duplicate-column": [command("addColumn", "t", column="v")],
                "commit": [command("commit")], "rollback": [command("rollback")],
                "begin": [command("beginTransaction"), command("beginTransaction")],
                "unique": [command("insert", "t", key=1)],
                "not-null": [command("update", "t", column="id", value=None)],
            }
            self.program.commands += options[error]

        def teardown(self) -> None:
            """The compiled classifier alone decides agreement; native properties add checks."""
            for program in (self.program, self.ddl):
                program.roundtrip(runtime / "build/sqlite-parser")
                case, result = acquire(program.fixture(), runtime)
                if case is not None:
                    native_laws(case)
                    result = compiled(case, runtime)
                    records.append(case)
                counts[result["verdict"]] += 1
                assert result["verdict"] == "AGREE", (program.fixture(), result)

    run_state_machine_as_test(seed(fixed_seed)(Machine), settings=settings(max_examples=examples,
        stateful_step_count=steps, deadline=None, database=None))
    return dict(counts), records
