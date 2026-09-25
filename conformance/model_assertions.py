"""Generate kernel-checked observation equalities against independently declared expectations."""

from migration_check.sql_model import lean_string
from model_cases import Case, Cell, ExpectedTable


def value(cell: Cell) -> str:
    """Embed exact observed text bytes without asking the model to coerce SQL values."""
    if cell is None:
        return ".null"
    if isinstance(cell, int):
        return f"(.integer ({cell}))"
    return ".text [" + ",".join(str(byte) for byte in cell.encode()) + "]"


def columns(table: ExpectedTable) -> str:
    """Use explicit trusted expected column declarations, not a model-produced schema."""
    return "[" + ",".join(f"{{ name := {lean_string(name)}, affinity := .{kind.lower()} }}"
                           for name, kind in table.columns) + "]"


def table_literal(table: ExpectedTable) -> str:
    """Preserve declared rowid order, multiplicity, and every expected cell."""
    rows = ",".join(f"⟨({row[0]}), [" + ",".join(value(cell) for cell in row[1:]) + "]⟩"
                    for row in table.rows)
    return f"{{ columns := {columns(table)}, rows := [{rows}] }}"


def assertions(case: Case) -> str:
    """Check the complete concrete result with kernel decide, never native_decide."""
    lines = ["open SqliteVerifier", "set_option maxRecDepth 30000",
             "set_option maxHeartbeats 5000000", "def before : Database :="]
    initial = "(fun _ => none)"
    for table in case.before:
        initial = f"Database.set ({initial}) {lean_string(table.name)} {table_literal(table)}"
    lines.append(initial)
    lines.extend([
        "def observed := runSql Generated.script before",
        "example : SupportedSql Generated.startSchema Generated.script before := by unfold SupportedSql; decide +kernel",
        "def closed : Outcome → Bool",
        "  | .pending .. => false", "  | _ => true",
        "example : closed observed = true := by decide +kernel",
        "def failureInfo : Outcome → Option (Nat × ExecutionError)",
        "  | .success _ => none", "  | .failure position reason _ => some (position, reason)",
        "  | .pending _ _ error => error",
        f"theorem checkedOutcome : failureInfo observed = {case.lean_failure} := by decide +kernel",
    ])
    expected_schema = "[" + ",".join(f"{{ name := {lean_string(table.name)}, columns := {columns(table)} }}"
                                      for table in case.after) + "]"
    lines.append(f"example : Generated.nextSchema = {expected_schema} := by decide +kernel")
    for table in case.before:
        lines.append(f"example : Generated.startSchema.lookup {lean_string(table.name)} = "
                     f"some {columns(table)} := by decide +kernel")
    for index, table in enumerate(case.after):
        lines.append(f"theorem checkedTable{index} : observed.database {lean_string(table.name)} = "
                     f"some {table_literal(table)} := by decide +kernel")
    lines.append('example : observed.database "unreached" = none := by decide +kernel')
    lines.append("#print axioms checkedOutcome")
    return "\n".join(lines) + "\n"
