"""Emit inert Lean constructors and the application-owned Generated input declarations."""

from belay.sqlite.profiles import DEFAULT_PROFILE, ExecutionProfile
from belay.sqlite.sql_model import Column, Index, Statement, Table, SqlValue, transition
from belay.sqlite.admission import admit
from belay.sqlite.quoted_text import quoted_string

def column_lean(column: Column) -> str:
    """Emit a structural constructor, never executable user-supplied Lean syntax."""
    fields = [f"name := {quoted_string(column.name)}", f"affinity := .{column.affinity}"]
    if column.declared_type != "canonical":
        fields.append(f"declaredType := .{column.declared_type}")
    if column.not_null:
        fields.append("notNull := true")
    if column.current_timestamp:
        fields.append("defaultValue := some .currentTimestamp")
    return "{ " + ", ".join(fields) + " }"


def lean_names(names: tuple[str, ...]) -> str:
    """Render an ordered key using inert identifier literals."""
    return "[" + ", ".join(map(quoted_string, names)) + "]"


def index_lean(index: Index) -> str:
    """Keep index identity and uniqueness bound to the generated schema."""
    return (f"{{ name := {quoted_string(index.name)}, columns := {lean_names(index.columns)}, "
            f"unique := {str(index.unique).lower()} }}")


def table_lean(table: Table) -> str:
    """Render only trusted constructors and quoted identifier literals."""
    keys = "[" + ", ".join(map(lean_names, table.unique_keys)) + "]"
    indexes = "[" + ", ".join(index_lean(index) for index in table.indexes) + "]"
    return (f"{{ name := {quoted_string(table.name)}, columns := [{', '.join(column_lean(c) for c in table.columns)}], "
            f"properties := {{ primaryKey := {lean_names(table.primary_key)}, "
            f"uniqueKeys := {keys}, indexes := {indexes} }} }}")


def statement_lean(statement: Statement) -> str:
    """Keep SQL strings inert when embedding the script in Lean."""
    if statement.kind in {'beginTransaction', 'commit', 'rollback'}:
        return f'.{statement.kind}'
    if statement.kind == 'insert':
        values = '[' + ', '.join(map(lean_value, statement.values)) + ']'
        return f'.insert {quoted_string(statement.table)} {lean_names(statement.names)} {values}'
    if statement.kind == 'update':
        return (f'.update {quoted_string(statement.table)} {quoted_string(statement.names[0])} '
                f'({lean_value(statement.values[0])}) {quoted_string(statement.key)} ({statement.equals})')
    columns = ", ".join(column_lean(column) for column in statement.columns)
    argument = f"[{columns}]" if statement.kind == "createTable" else columns
    return f".{statement.kind} {quoted_string(statement.table)} {argument}"


def schema_inputs(schema: tuple[Table, ...]) -> str:
    """Expose only parsed starting schema to the sealed approved interpretation stage."""
    start = ", ".join(table_lean(table) for table in schema)
    return ("import SqliteVerifier\n\nnamespace Generated\nopen Belay.Sqlite\n"
            f"def startSchema : Schema := [{start}]\nend Generated\n")


def sql_inputs(schema: tuple[Table, ...], script: tuple[Statement, ...],
               execution_profile: ExecutionProfile = DEFAULT_PROFILE) -> str:
    """Bind the candidate-independent parsed inputs in a separately sealed module."""
    admit(schema, script)
    result, _ = transition(schema, script)
    after = "startSchema" if result == schema else "[" + ", ".join(table_lean(table) for table in result) + "]"
    commands = ", ".join(statement_lean(statement) for statement in script)
    return ("import SchemaInputs\n\nnamespace Generated\nopen Belay.Sqlite\n"
            f"def nextSchema : Schema := {after}\n"
            f"def script : List Statement := [{commands}]\n"
            f"def profile : ExecutionProfile := {'.' + execution_profile.wire_tag}\nend Generated\n")


def lean_value(value: SqlValue) -> str:
    """Use bytes for SQLite TEXT/BLOB values and never interpolate executable source."""
    if value is None:
        return '.null'
    if isinstance(value, int):
        return f'.integer ({value})'
    kind, data = ('text', value.encode('utf-8')) if isinstance(value, str) else ('blob', value)
    return f'.{kind} [' + ', '.join(map(str, data)) + ']'

