"""Bounded Hypothesis stateful generation in well-scoped and error-seeking modes."""

from collections import Counter
from pathlib import Path

from hypothesis import settings, seed, strategies as st
from hypothesis.stateful import RuleBasedStateMachine, initialize, rule, run_state_machine_as_test

from conformance.case_format import Json
from conformance.generated_program import Program, command, native_laws
from conformance.model_check import acquire, compiled
from conformance.native_record import record_sql
from conformance.native_replay import prepare
from migration_check.sql_model import Affinity
from migration_check.sql_values import SqlValue

VALUES = {
    "blob": [None, "", "1", " 1", "1.0", "a'\nb", b"", b"\x00\xff", -(2**63), 2**63-1],
    "text": [None, "", "1", " 1", "1.0", "a'\nb", b"\x00\xff"],
    "integer": [None, -2**63, 0, 2**63-1, "abc", b"\x00"],
    "numeric": [None, -2**63, 0, 2**63-1, "abc", b"\x00"],
    "real": [None, b"", b"\x00\xff"],
}


def generate(runtime: Path, *, error_seeking: bool, examples: int = 20, steps: int = 8,
             fixed_seed: int = 4004) -> tuple[dict[str, int], list[dict[str, Json]], list[dict[str, Json]]]:
    """Hypothesis shrinks failed executions; fixed seeds and bounded settings make CI repeatable."""
    counts: Counter[str] = Counter()
    records: list[dict[str, Json]] = []
    boundaries: list[dict[str, Json]] = []

    class Machine(RuleBasedStateMachine):
        """Each action appends constructors; state chooses fresh table and key names."""
        def __init__(self) -> None:
            super().__init__()
            self.program = Program()
            self.ddl = Program(schema="CREATE TABLE exists_table(v BLOB);",
                               rows={"exists_table": [(7, ((4, b"x"),))]})
            self.affinity: Affinity = "blob"
            self.boundary = "1"
            self.serial = 1

        @initialize(affinity=st.sampled_from(list(VALUES)))
        def configure(self, affinity: Affinity) -> None:
            """Vary declared affinity while keeping the initial key and value admissible."""
            self.affinity = affinity
            self.program = Program(schema=f"CREATE TABLE t(id INTEGER NOT NULL,v {affinity.upper()},UNIQUE(id));",
                                   rows={"t": [(1, ((1, 1), (5, None)))]})

        @rule(choice=st.integers(min_value=0, max_value=30))
        def write(self, choice: int) -> None:
            """Write a distinct admitted value so ignored UPDATE mutations are observable."""
            value = VALUES[self.affinity][choice % len(VALUES[self.affinity])]
            changed = b"changed" if value is None else None
            self.serial += 1
            self.program.commands += [command("insert", "t", key=self.serial, value=value),
                                      command("update", "t", key=self.serial, value=changed)]

        @rule(rollback=st.booleans(), choice=st.integers(min_value=0, max_value=30))
        def transaction(self, rollback: bool, choice: int) -> None:
            """Exercise explicit commit/rollback around a successful body."""
            value = VALUES[self.affinity][choice % len(VALUES[self.affinity])]
            self.serial += 1
            self.program.commands += [command("beginTransaction"),
                command("insert", "t", key=self.serial, value=value),
                command("rollback" if rollback else "commit")]

        @rule(value=st.sampled_from(["1", " 1", "1.0", "1e20"]))
        def affinity_boundary(self, value: str) -> None:
            """Keep conversion evidence outside the current lossless model domain."""
            self.boundary = value

        @rule()
        def schema_change(self) -> None:
            """Fresh auxiliary tables permit ADD without changing the DML fixture shape."""
            self.serial += 1
            name = f"a{self.serial}"
            self.ddl.commands += [command("createTable", name, affinity=self.affinity),
                                  command("addColumn", "exists_table", column=f"extra{self.serial}", affinity=self.affinity)]

        @rule(error=st.sampled_from(["duplicate-table", "missing-table", "duplicate-column", "commit", "rollback", "begin", "unique", "not-null"]))
        def error(self, error: str) -> None:
            """Error mode admits ordinary SQL failures; well-scoped mode keeps making writes."""
            if not error_seeking:
                self.write(0)
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
            if error_seeking:
                self.program.commands.append(command("insert", "t", key=1))
            for program in (self.program, self.ddl):
                program.roundtrip(runtime / "build/sqlite-parser")
                case, result = acquire(program.fixture(), runtime)
                if case is not None:
                    native_laws(case)
                    result = compiled(case, runtime)
                    records.append(case)
                counts[result["verdict"]] += 1
                assert result["verdict"] in {"AGREE", "MODEL_UNSUPPORTED"}, (program.fixture(), result)
            native = record_sql("CREATE TABLE t(v INTEGER);",
                "INSERT INTO t(v) VALUES('" + self.boundary + "');", name="generated-affinity-boundary")
            case, result = prepare(native, runtime / "build/sqlite-parser")
            if case is not None:
                result = compiled(case, runtime)
                records.append(case)
            boundaries.append({"record": native, "classification": result})
            counts[result["verdict"]] += 1
            assert result["verdict"] in {"AGREE", "MODEL_UNSUPPORTED"}, result

    run_state_machine_as_test(seed(fixed_seed)(Machine), settings=settings(max_examples=examples,
        stateful_step_count=steps, deadline=None, database=None))
    return dict(counts), records, boundaries
