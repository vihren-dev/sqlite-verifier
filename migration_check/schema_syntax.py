"""Admit baseline column/key productions without widening migration operations."""

from typing import cast

from .sql_model import Affinity, Column, DeclaredType
from .sql_tree import Node, Tree
from .translate import empty, identifier, normalize


def key_columns(tree: Tree, node: Node) -> tuple[str, ...]:
    """Accept ordered plain column references, without expressions or sort modifiers."""
    names: list[str] = []
    while True:
        members = tree.children(node)
        symbols = [item.symbol for item in members]
        if symbols == ["sortlist", "COMMA", "expr", "sortorder", "nulls"]:
            prior, expression, order, nulls = members[0], *members[2:]
        elif symbols == ["expr", "sortorder", "nulls"]:
            prior = None
            expression, order, nulls = members
        else:
            raise tree.unsupported(node, "Unsupported key column list")
        empty(tree, order)
        empty(tree, nulls)
        tokens = tree.children(expression)
        if len(tokens) != 1 or tokens[0].symbol != "ID":
            raise tree.unsupported(expression, "Keys require plain column references")
        names.append(identifier(tree, tokens[0]))
        if prior is None:
            break
        node = prior
    return tuple(reversed(names))


def baseline_column(tree: Tree, node: Node, constraints: Node) -> tuple[Column, bool]:
    """Retain exact supported type aliases, explicit nullability and timestamp default."""
    members = tree.children(node)
    if [item.symbol for item in members] != ["nm", "typetoken"]:
        raise tree.unsupported(node, "Unsupported column definition")
    types = tree.children(members[1])
    tokens = tree.children(types[0]) if len(types) == 1 and types[0].symbol == "typename" else []
    spelling = normalize(tree.text(tokens[0])) if len(tokens) == 1 and tokens[0].symbol == "ID" else ""
    aliases: dict[str, tuple[Affinity, DeclaredType]] = {
        "bigint": ("integer", "bigInt"), "timestamp": ("numeric", "timestamp"),
        "boolean": ("numeric", "boolean"),
    }
    if not types:
        affinity, declared = "blob", "untyped"
    elif spelling in aliases:
        affinity, declared = aliases[spelling]
    elif spelling in {"integer", "real", "text", "blob", "numeric"}:
        affinity, declared = cast(Affinity, spelling), "canonical"
    else:
        raise tree.unsupported(members[1], "Declared type is outside the supported baseline subset")
    seen: set[str] = set()
    while constraints.children:
        children = tree.children(constraints)
        if [item.symbol for item in children] != ["carglist", "ccons"]:
            raise tree.unsupported(constraints, "Unsupported column constraints")
        constraint = children[1]
        parts = tree.children(constraint)
        symbols = [item.symbol for item in parts]
        if symbols == ["NOT", "NULL", "onconf"]:
            kind = "notNull"
            empty(tree, parts[2])
        elif symbols == ["PRIMARY", "KEY", "sortorder", "onconf", "autoinc"]:
            kind = "primaryKey"
            for option in parts[2:]:
                empty(tree, option)
        elif symbols == ["DEFAULT", "scantok", "term"]:
            kind = "default"
            term = tree.children(parts[2])
            if (len(term) != 1 or term[0].symbol != "CTIME_KW" or
                    normalize(tree.text(term[0])) != "current_timestamp"):
                raise tree.unsupported(constraint, "Only the CURRENT_TIMESTAMP baseline default is modeled")
        else:
            raise tree.unsupported(constraint, "Unsupported baseline column constraint")
        if kind in seen:
            raise tree.unsupported(constraint, "Repeated column constraints are unsupported")
        seen.add(kind)
        constraints = children[0]
    definition = Column(identifier(tree, members[0]), affinity,
                        cast(DeclaredType, declared), "notNull" in seen, "default" in seen)
    return definition, "primaryKey" in seen


def unique_keys(tree: Tree, node: Node) -> tuple[tuple[str, ...], ...]:
    """Retain unnamed table UNIQUE constraints; reject every other table constraint."""
    if not node.children:
        return ()
    optional = tree.children(node)
    if [item.symbol for item in optional] != ["COMMA", "conslist"]:
        raise tree.unsupported(node, "Unsupported table constraints")
    current = optional[1]
    keys: list[tuple[str, ...]] = []
    while True:
        members = tree.children(current)
        symbols = [item.symbol for item in members]
        if symbols == ["tcons"]:
            prior, constraint = None, members[0]
        elif symbols == ["conslist", "tconscomma", "tcons"]:
            prior, constraint = members[0], members[2]
        else:
            raise tree.unsupported(current, "Unsupported table constraint list")
        parts = tree.children(constraint)
        if [item.symbol for item in parts] != ["UNIQUE", "LP", "sortlist", "RP", "onconf"]:
            raise tree.unsupported(constraint, "Only unnamed UNIQUE table constraints are modeled")
        empty(tree, parts[4])
        keys.append(key_columns(tree, parts[2]))
        if prior is None:
            break
        current = prior
    return tuple(reversed(keys))
