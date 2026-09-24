"""The deliberately small typed SQL input to the sealed Lean representation."""

from dataclasses import dataclass
from typing import Literal

Affinity = Literal["integer", "real", "text", "blob", "numeric"]


def lean_string(value: str) -> str:
    """Use Lean's Unicode escapes for controls; JSON's backspace/formfeed escapes differ."""
    escapes = {ord('"'): '\\"', ord('\\'): '\\\\'}
    escapes.update({number: f"\\u{number:04x}" for number in range(32)})
    return '"' + value.translate(escapes) + '"'


@dataclass(frozen=True)
class Column:
    """A supported nullable column without constraints or an explicit default."""

    name: str
    affinity: Affinity

    def lean(self) -> str:
        """Emit a structural constructor, never executable user-supplied Lean syntax."""
        return f"⟨{lean_string(self.name)}, .{self.affinity}⟩"


@dataclass(frozen=True)
class Table:
    """A normalized ordinary rowid table in the finite starting or resulting schema."""

    name: str
    columns: tuple[Column, ...]

    def lean(self) -> str:
        """Render only trusted constructors and quoted identifier literals."""
        return f"⟨{lean_string(self.name)}, [{', '.join(c.lean() for c in self.columns)}]⟩"


@dataclass(frozen=True)
class Statement:
    """One admitted command with original coordinates for generated diagnostics."""

    kind: Literal["createTable", "addColumn"]
    table: str
    columns: tuple[Column, ...]
    source: str
    start: int
    end: int

    def lean(self) -> str:
        """Keep SQL strings inert when embedding the script in Lean."""
        columns = ", ".join(column.lean() for column in self.columns)
        argument = f"[{columns}]" if self.kind == "createTable" else columns
        return f".{self.kind} {lean_string(self.table)} {argument}"


def transition(schema: tuple[Table, ...], script: tuple[Statement, ...]) -> tuple[tuple[Table, ...], str]:
    """Compute schema effects, stopping at the same first modeled error as execution."""
    tables = list(schema)
    for statement in script:
        found = next((i for i, table in enumerate(tables) if table.name == statement.table), None)
        if statement.kind == "createTable":
            if found is not None:
                return tuple(tables), "tableExists"
            tables.append(Table(statement.table, statement.columns))
        elif found is None:
            return tuple(tables), "missingTable"
        elif len(tables[found].columns) >= 2000:
            return tuple(tables), "tooManyColumns"
        elif statement.columns[0].name in {column.name for column in tables[found].columns}:
            return tuple(tables), "columnExists"
        else:
            tables[found] = Table(statement.table, tables[found].columns + statement.columns)
    return tuple(tables), ""


def sql_inputs(schema: tuple[Table, ...], script: tuple[Statement, ...]) -> str:
    """Bind the candidate-independent parsed inputs in a separately sealed module."""
    result, _ = transition(schema, script)
    start = ", ".join(table.lean() for table in schema)
    after = ", ".join(table.lean() for table in result)
    commands = ", ".join(statement.lean() for statement in script)
    return ("import SqliteVerifier\n\nnamespace Generated\nopen SqliteVerifier\n"
            f"def startSchema : Schema := [{start}]\n"
            f"def nextSchema : Schema := [{after}]\n"
            f"def script : List Statement := [{commands}]\nend Generated\n")
