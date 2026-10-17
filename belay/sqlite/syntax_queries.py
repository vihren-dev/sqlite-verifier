"""Map the expressions and result columns of a query to statement syntax (ADR 0012).

A result column keeps its source text, which SQLite uses as the column name; `*` and
`source.*` select columns. Inside a query, an expression may also be a qualified
name `source.column`,  a comparison, AND, OR, NOT,
IS NULL, arithmetic, unary minus or plus of any expression, CAST with its type
name as written, or a function call with `*` or with one or more arguments, with
the function name as written: Lean folds the name and decides the function. A call
with two or more arguments is a `callPair`, whose arguments after the second are `more`
nodes. The operators `->` and `->>`
are a `callPair` of the function named `->` or `->>`, as SQLite's parser makes them
calls of those functions (ADR 0012, amendment 5, slice 6b). Other statements keep
the expressions of `syntax_expressions.expression`. A schema-qualified column and a
call without arguments have no constructor and are refused with their source range;
`syntax_select` maps the SELECT statement.
"""

from .located import Located, constructor, leaf, sequence, structure
from .sql_tree import Node, Tree
from .syntax_definitions import absent, left_list, require
from .syntax_expressions import dequote, expression, name

COMPARISONS = {"NE": "ne", "LT": "lt", "LE": "le", "GT": "gt", "GE": "ge"}
"""Comparison tokens other than `=`, and their `Comparison` constructors in Lean."""
CONNECTIVES = {"AND": "and", "OR": "or"}
"""Logical tokens and their `Syntax.Expr` constructors in Lean."""
ARITHMETIC = {"PLUS": "add", "MINUS": "subtract", "STAR": "multiply", "SLASH": "divide", "REM": "remainder"}
"""Arithmetic tokens and their `ArithmeticOperator` constructors in Lean."""


def binary(tree: Tree, node: Node, kind: str, left: Node, right: Node) -> Located:
    """A constructor with a left and a right operand."""
    return constructor(kind, [("left", query_expression(tree, left)), ("right", query_expression(tree, right))],
                       node.start, node.end)


def compare(tree: Tree, node: Node, operator: str, left: Node, right: Node, kind: str = "compare") -> Located:
    """A comparison other than `=`, or an arithmetic operator: a constructor with an
    operator and two operands."""
    return constructor(kind, [("operator", leaf(operator, node.start, node.end)),
                                   ("left", query_expression(tree, left)),
                                   ("right", query_expression(tree, right))], node.start, node.end)


def is_null(tree: Tree, node: Node, operand: Node, negated: bool) -> Located:
    """`IS NULL`, `ISNULL`, `NOTNULL` or `NOT NULL`."""
    return constructor("isNull", [("operand", query_expression(tree, operand)),
                                  ("negated", leaf(negated, node.start, node.end))], node.start, node.end)


def argument_rest(tree: Tree, start: int, end: int, arguments: list[Node]) -> Located:
    """The arguments after the first over a byte range: the last argument, or a `more` node
    of the next argument and the arguments after it."""
    if len(arguments) == 1:
        return query_expression(tree, arguments[0])
    return constructor("more", [("first", query_expression(tree, arguments[0])),
                                ("rest", argument_rest(tree, arguments[1].start, end, arguments[1:]))], start, end)


def call_pairs(tree: Tree, start: int, end: int, function: Located, arguments: list[Node]) -> Located:
    """Two or more arguments as a `callPair` over a byte range: the first argument, and the
    others (`argument_rest`), so that `f(a, b, c)` and `f(a, g(b, c))` stay distinct."""
    return constructor("callPair", [("name", function), ("first", query_expression(tree, arguments[0])),
                                    ("rest", argument_rest(tree, arguments[1].start, end, arguments[1:]))], start, end)


def function_call(tree: Tree, node: Node, children: list[Node]) -> Located:
    """A call with `*`, without arguments, or with one or more arguments, with the function
    name as written."""
    function = name(tree, children[0])
    if [child.symbol for child in children] == ["ID", "LP", "STAR", "RP"]:
        return constructor("callStar", [("name", function)], node.start, node.end)
    if [child.symbol for child in children] == ["ID", "LP", "distinct", "exprlist", "RP"]:
        absent(tree, children[2], "DISTINCT in a function call")
        arguments = left_list(tree, children[3], {1: ["nexprlist"]})
        items = left_list(tree, arguments[0][0], {1: ["expr"], 3: ["nexprlist", "COMMA", "expr"]}) if arguments else []
        if not items:
            return constructor("callEmpty", [("name", function)], node.start, node.end)
        if len(items) == 1:
            return constructor("call", [("name", function), ("operand", query_expression(tree, items[0][-1]))],
                               node.start, node.end)
        if len(items) > 1:
            return call_pairs(tree, node.start, node.end, function, [item[-1] for item in items])
    raise tree.unsupported(node, "Only COUNT(*), COUNT, MIN, MAX, SUM and AVG of one argument, and COALESCE are modeled as functions")


def query_expression(tree: Tree, node: Node) -> Located:
    """Map an `expr` production of a query, or refuse it with its range."""
    children = tree.children(node)
    symbols = [child.symbol for child in children]
    if symbols == ["LP", "expr", "RP"]:
        return query_expression(tree, children[1])
    if len(symbols) == 3 and symbols[0] == symbols[2] == "expr":
        if symbols[1] == "EQ":
            return binary(tree, node, "equals", children[0], children[2])
        if symbols[1] in COMPARISONS:
            return compare(tree, node, COMPARISONS[symbols[1]], children[0], children[2])
        if symbols[1] == "IS":
            return compare(tree, node, "is", children[0], children[2])
        if symbols[1] in CONNECTIVES:
            return binary(tree, node, CONNECTIVES[symbols[1]], children[0], children[2])
        if symbols[1] in ARITHMETIC:
            return compare(tree, node, ARITHMETIC[symbols[1]], children[0], children[2], "arithmetic")
    if symbols == ["expr", "PTR", "expr"]:
        operator = leaf(tree.text(children[1]), children[1].start, children[1].end)
        return constructor("callPair", [("name", operator), ("first", query_expression(tree, children[0])),
                                        ("rest", query_expression(tree, children[2]))], node.start, node.end)
    if symbols == ["expr", "IS", "NOT", "expr"]:
        return compare(tree, node, "isNot", children[0], children[3])
    if symbols in (["MINUS", "expr"], ["PLUS", "expr"]):
        kind = "negate" if symbols[0] == "MINUS" else "positive"
        return constructor(kind, [("operand", query_expression(tree, children[1]))], node.start, node.end)
    if symbols == ["CAST", "LP", "expr", "AS", "typetoken", "RP"]:
        return constructor("cast", [("operand", query_expression(tree, children[2])),
                                    ("typeName", leaf(tree.text(children[4]), children[4].start, children[4].end))],
                           node.start, node.end)
    if symbols == ["nm", "DOT", "nm"]:
        return constructor("qualified", [("source", name(tree, children[0])), ("column", name(tree, children[2]))],
                           node.start, node.end)
    if symbols == ["nm", "DOT", "nm", "DOT", "nm"]:
        raise tree.unsupported(node, "A schema-qualified column is not modeled; write source.column")
    if symbols == ["NOT", "expr"]:
        return constructor("not", [("operand", query_expression(tree, children[1]))], node.start, node.end)
    if symbols in (["expr", "ISNULL"], ["expr", "NOTNULL"], ["expr", "NOT", "NULL"]):
        return is_null(tree, node, children[0], symbols[1] != "ISNULL")
    if symbols[:2] == ["ID", "LP"]:
        return function_call(tree, node, children)
    return expression(tree, node)


def result_column(tree: Tree, node: Node, parts: list[Node]) -> Located:
    """Map `*`, `source.*`, or an expression with its optional alias and its source text."""
    symbols = [part.symbol for part in parts]
    if symbols == ["scanpt", "STAR"]:
        return leaf("star", parts[1].start, parts[1].end)
    if symbols == ["scanpt", "nm", "DOT", "STAR"]:
        return constructor("sourceStar", [("source", name(tree, parts[1]))], parts[1].start, parts[3].end)
    if symbols != ["scanpt", "expr", "scanpt", "as"]:
        raise tree.unsupported(node, "Only `*` and expressions are modeled as result columns; write the column names")
    alias_parts = tree.children(parts[3])
    if [part.symbol for part in alias_parts] == ["AS", "nm"]:
        alias = name(tree, alias_parts[1])
    elif alias_parts:
        alias = leaf(dequote(tree.text(alias_parts[0])), parts[3].start, parts[3].end)
    else:
        alias = leaf(None, parts[3].start, parts[3].end)
    value = parts[1]
    return constructor("expression", [("value", query_expression(tree, value)), ("alias", alias),
                                      ("text", leaf(tree.text(value), value.start, value.end))],
                       value.start, max(value.end, parts[3].end))


def result_columns(tree: Tree, node: Node) -> Located:
    """Map the result column list in source order."""
    items: list[Located] = []
    current = node
    while True:
        children = tree.children(current)
        items.append(result_column(tree, current, children[1:]))
        nested = tree.children(children[0])
        if not nested:
            break
        current = require(tree, children[0], ["selcollist", "COMMA"])[0]
    items.reverse()
    return sequence(items, node.start, node.end)
