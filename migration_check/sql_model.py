"""The deliberately small typed SQL input to the sealed Lean representation."""

from dataclasses import dataclass, replace
from typing import Literal

from .profiles import ExecutionProfile, LEGACY_PROFILE
from .diagnostics import Rejection

Affinity = Literal["integer", "real", "text", "blob", "numeric"]
DeclaredType = Literal["canonical", "bigInt", "timestamp", "boolean", "untyped"]


def lean_string(value: str) -> str:
    """Use Lean's Unicode escapes for controls; JSON's backspace/formfeed escapes differ."""
    escapes = {ord('"'): '\\"', ord('\\'): '\\\\'}
    escapes.update({number: f"\\u{number:04x}" for number in range(32)})
    return '"' + value.translate(escapes) + '"'


@dataclass(frozen=True)
class Column:
    """A column with exact supported declared type and baseline constraint metadata."""

    name: str
    affinity: Affinity
    declared_type: DeclaredType = "canonical"
    not_null: bool = False
    current_timestamp: bool = False

    def lean(self) -> str:
        """Emit a structural constructor, never executable user-supplied Lean syntax."""
        fields = [f"name := {lean_string(self.name)}", f"affinity := .{self.affinity}"]
        if self.declared_type != "canonical":
            fields.append(f"declaredType := .{self.declared_type}")
        if self.not_null:
            fields.append("notNull := true")
        if self.current_timestamp:
            fields.append("defaultValue := some .currentTimestamp")
        return "{ " + ", ".join(fields) + " }"


def lean_names(names: tuple[str, ...]) -> str:
    """Render an ordered key using inert identifier literals."""
    return "[" + ", ".join(map(lean_string, names)) + "]"


@dataclass(frozen=True)
class Index:
    """An ordinary explicit index over existing columns, with BINARY collation."""

    name: str
    columns: tuple[str, ...]
    unique: bool = False

    def lean(self) -> str:
        """Keep index identity and uniqueness bound to the generated schema."""
        return (f"{{ name := {lean_string(self.name)}, columns := {lean_names(self.columns)}, "
                f"unique := {str(self.unique).lower()} }}")


@dataclass(frozen=True)
class Table:
    """A normalized ordinary rowid table in the finite starting or resulting schema."""

    name: str
    columns: tuple[Column, ...]
    primary_key: tuple[str, ...] = ()
    unique_keys: tuple[tuple[str, ...], ...] = ()
    indexes: tuple[Index, ...] = ()

    def lean(self) -> str:
        """Render only trusted constructors and quoted identifier literals."""
        keys = "[" + ", ".join(map(lean_names, self.unique_keys)) + "]"
        indexes = "[" + ", ".join(index.lean() for index in self.indexes) + "]"
        return (f"{{ name := {lean_string(self.name)}, columns := [{', '.join(c.lean() for c in self.columns)}], "
                f"properties := {{ primaryKey := {lean_names(self.primary_key)}, "
                f"uniqueKeys := {keys}, indexes := {indexes} }} }}")


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
            tables[found] = replace(tables[found], columns=tables[found].columns + statement.columns)
    return tuple(tables), ""


def sql_inputs(schema: tuple[Table, ...], script: tuple[Statement, ...],
               execution_profile: ExecutionProfile = LEGACY_PROFILE, migration_bytes: bytes | None = None) -> str:
    """Bind the candidate-independent parsed inputs in a separately sealed module."""
    from .schema_translate import validate_migration
    validate_migration(schema, script)
    if execution_profile.engine == "3.46.0":
        if migration_bytes is not None and migration_bytes.startswith(b"-- no-transaction"):
            raise Rejection("UNSUPPORTED", "SQLx no-transaction directives are outside the atomic runner profile")
        for statement in script:
            if statement.kind != "addColumn" or statement.table == "_sqlx_migrations":
                raise Rejection("UNSUPPORTED", "SQLx payloads require plain ADD outside bookkeeping tables",
                                source=statement.source, start=statement.start, end=statement.end)
    result, _ = transition(schema, script)
    start = ", ".join(table.lean() for table in schema)
    after = "startSchema" if result == schema else "[" + ", ".join(table.lean() for table in result) + "]"
    commands = ", ".join(statement.lean() for statement in script)
    return ("import SqliteVerifier\n\nnamespace Generated\nopen SqliteVerifier\n"
            f"def startSchema : Schema := [{start}]\n"
            f"def nextSchema : Schema := {after}\n"
            f"def script : List Statement := [{commands}]\n"
            f"def profile : ExecutionProfile := {execution_profile.lean(migration_bytes)}\nend Generated\n")
