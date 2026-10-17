"""Map a parsed SQL script to statement syntax and build the structural record.

The frontend maps each parser production to one constructor of the Lean
`Syntax.Statement`, refuses syntax without a constructor, and keeps the source
range of every node. It reads no schema: Lean resolves names, types, values and
limits. The record carries the profile's release and build and both scripts.
"""

from .located import Json, Located
from .profiles import ExecutionProfile
from .sql_tree import Node, Tree
from .syntax_definitions import add_column, create_index, create_table
from .syntax_select import select
from .syntax_writes import delete, insert, transaction, update

SCRIPT_RECORD_VERSION = 3
"""The version of the structural record that Lean's `decodeScriptRecord` accepts."""


def commands(tree: Tree) -> list[Node]:
    """Return each command of the script; refuse wrappers such as EXPLAIN."""
    result: list[Node] = []
    for node in tree.walk(tree.nodes[tree.root]):
        if node.symbol != "ecmd":
            continue
        members = tree.children(node)
        if [child.symbol for child in members] == ["SEMI"]:
            continue
        if [child.symbol for child in members] != ["cmdx", "SEMI"]:
            raise tree.unsupported(node, "Unsupported command wrapper, such as EXPLAIN; remove it")
        result.append(tree.children(members[0])[0])
    return result


def statement(tree: Tree, command: Node) -> Located:
    """Map one command, or refuse a statement that has no syntax constructor."""
    symbols = [child.symbol for child in tree.children(command)]
    if symbols == ["create_table", "create_table_args"]:
        return create_table(tree, command)
    if symbols[:3] == ["createkw", "uniqueflag", "INDEX"]:
        return create_index(tree, command)
    if symbols[:2] == ["ALTER", "TABLE"]:
        return add_column(tree, command)
    if symbols[:1] in (["BEGIN"], ["COMMIT"], ["END"], ["ROLLBACK"]):
        return transaction(tree, command)
    if symbols[:2] == ["with", "insert_cmd"]:
        return insert(tree, command)
    if symbols[:2] == ["with", "UPDATE"]:
        return update(tree, command)
    if symbols[:2] == ["with", "DELETE"]:
        return delete(tree, command)
    if symbols == ["select"]:
        return select(tree, command)
    raise tree.unsupported(command, "This statement is not modeled; the model runs CREATE TABLE, CREATE INDEX, "
                           "ALTER TABLE ADD COLUMN, BEGIN, COMMIT, ROLLBACK, INSERT, UPDATE, DELETE and SELECT")


def statements(tree: Tree) -> tuple[Located, ...]:
    """Map every command of a parsed script, in order."""
    return tuple(statement(tree, command) for command in commands(tree))


def script_record(profile: ExecutionProfile, schema: tuple[Located, ...],
                  script: tuple[Located, ...]) -> dict[str, Json]:
    """Build the structural record of a schema and a script for the given profile."""
    return {"version": SCRIPT_RECORD_VERSION, "release": profile.engine, "sourceId": profile.source_id,
            "schema": [item.value for item in schema], "script": [item.value for item in script]}
