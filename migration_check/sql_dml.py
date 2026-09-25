"""Admit complete generic transaction and literal-write grammar productions."""

from .sql_model import Statement
from .sql_tree import Node, Tree
from .sql_values import literal
from .translate import empty, identifier


def members(tree: Tree, node: Node, expected: list[str]) -> list[Node]:
    """Optional syntax cannot disappear while narrowing a native CST production."""
    children = tree.children(node)
    if [child.symbol for child in children] != expected:
        raise tree.unsupported(node, 'SQL form is outside the supported literal-write subset')
    return children


def comma_list(tree: Tree, node: Node, item: str) -> list[Node]:
    """Flatten the exact left-recursive native list, preserving each source operand."""
    result: list[Node] = []
    symbol = node.symbol
    while True:
        children = tree.children(node)
        if [child.symbol for child in children] == [item]:
            return [children[0], *reversed(result)]
        left, _, right = members(tree, node, [symbol, 'COMMA', item])
        result.append(right)
        node = left


def table_name(tree: Tree, node: Node) -> str:
    """Only unqualified ordinary main-database table names are admitted."""
    return identifier(tree, members(tree, node, ['nm'])[0], table=True)


def transaction(tree: Tree, command: Node) -> Statement:
    """Explicit transaction control never adds an implicit commit or rollback."""
    children = tree.children(command)
    token = children[0].symbol
    kind = {'BEGIN': 'beginTransaction', 'COMMIT': 'commit', 'END': 'commit', 'ROLLBACK': 'rollback'}[token]
    if token == 'BEGIN':
        _, mode, option = members(tree, command, ['BEGIN', 'transtype', 'trans_opt'])
        if [child.symbol for child in tree.children(mode)] not in ([], ['DEFERRED']):
            raise tree.unsupported(mode, 'Only deferred BEGIN transactions are modeled')
    else:
        _, option = members(tree, command, [token, 'trans_opt'])
    if [child.symbol for child in tree.children(option)] not in ([], ['TRANSACTION']):
        raise tree.unsupported(option, 'Named transaction syntax is outside the supported subset')
    if kind == 'beginTransaction':
        return Statement('beginTransaction', '', (), tree.source, command.start, command.end)
    if kind == 'commit':
        return Statement('commit', '', (), tree.source, command.start, command.end)
    return Statement('rollback', '', (), tree.source, command.start, command.end)


def insert(tree: Tree, command: Node) -> Statement:
    """One explicit VALUES row has no defaults, conflict overrides or implicit application work."""
    with_, operation, _, name, columns, select, upsert = members(tree, command,
        ['with', 'insert_cmd', 'INTO', 'xfullname', 'idlist_opt', 'select', 'upsert'])
    _, conflict = members(tree, operation, ['INSERT', 'orconf'])
    for option in (with_, conflict, upsert):
        empty(tree, option)
    _, names, _ = members(tree, columns, ['LP', 'idlist', 'RP'])
    decoded = tuple(identifier(tree, node) for node in comma_list(tree, names, 'nm'))
    current = select
    for symbol in ('selectnowith', 'oneselect', 'values'):
        current = members(tree, current, [symbol])[0]
    _, _, values, _ = members(tree, current, ['VALUES', 'LP', 'nexprlist', 'RP'])
    decoded_values = tuple(literal(tree, node) for node in comma_list(tree, values, 'expr'))
    if len(decoded) != len(decoded_values) or len(set(decoded)) != len(decoded) or len(decoded) > 2000:
        raise tree.unsupported(command, 'INSERT requires matching distinct explicit columns and values')
    return Statement('insert', table_name(tree, name), (), tree.source, command.start, command.end,
                     names=decoded, values=decoded_values)


def update(tree: Tree, command: Node) -> Statement:
    """A single literal assignment selects rows by one integer equality predicate."""
    with_, _, conflict, name, indexed, _, assignment, from_, where = members(tree, command,
        ['with', 'UPDATE', 'orconf', 'xfullname', 'indexed_opt', 'SET', 'setlist', 'from', 'where_opt_ret'])
    for option in (with_, conflict, indexed, from_):
        empty(tree, option)
    column, _, value = members(tree, assignment, ['nm', 'EQ', 'expr'])
    _, predicate = members(tree, where, ['WHERE', 'expr'])
    left, _, right = members(tree, predicate, ['expr', 'EQ', 'expr'])
    key = identifier(tree, members(tree, left, ['ID'])[0])
    equals = literal(tree, right)
    if type(equals) is not int:
        raise tree.unsupported(right, 'UPDATE predicate requires a decimal int64 equality literal')
    return Statement('update', table_name(tree, name), (), tree.source, command.start, command.end,
                     names=(identifier(tree, column),), values=(literal(tree, value),), key=key, equals=equals)
