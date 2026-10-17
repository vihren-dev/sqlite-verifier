import Belay.Sqlite.Resolution.Scope

set_option doc.verso true

/-! Questions about an expression as written over the sources in scope, which resolution
asks before it resolves the expression: whether it names a result column alias, and
whether it reads a column. -/

namespace Belay.Sqlite

/-- Whether an expression names a result column alias: an identifier that names no
column in scope but, after ASCII folding, is one of {lit}`aliases`. SQLite
resolves such a name in {lit}`WHERE` and inside {lit}`ORDER BY` expressions to the
aliased result expression, before the double-quoted string fallback. -/
def namesAlias (scope : Scope) (aliases : List String) : Syntax.Expr → Bool
  | .identifier name _ => (scope.matches name).isEmpty &&
      aliases.any (normalizeIdentifier · == normalizeIdentifier name)
  | .equals left right | .compare _ left right | .and left right | .or left right =>
    namesAlias scope aliases left || namesAlias scope aliases right
  | .arithmetic _ left right | .callPair _ left right | .more left right =>
    namesAlias scope aliases left || namesAlias scope aliases right
  | .not operand | .isNull operand _ | .call _ operand | .negate operand | .positive operand | .cast operand _ =>
    namesAlias scope aliases operand
  | .null | .numeric _ | .string _ | .blob _ | .currentTime _ | .callStar _ | .callEmpty _ | .qualified .. => false

/-- Whether an expression names a column in scope: an identifier with the folded name of
a column, or a qualified name of one, anywhere in the expression. A write value that names a column
depends on the row. -/
def mentionsColumn (scope : Scope) : Syntax.Expr → Bool
  | .identifier name _ => !(scope.matches name).isEmpty
  | .qualified source column => (scope.qualified source column).isSome
  | .equals left right | .compare _ left right | .and left right | .or left right
  | .arithmetic _ left right | .callPair _ left right | .more left right =>
    mentionsColumn scope left || mentionsColumn scope right
  | .not operand | .isNull operand _ | .call _ operand | .negate operand | .positive operand | .cast operand _ =>
    mentionsColumn scope operand
  | .null | .numeric _ | .string _ | .blob _ | .currentTime _ | .callStar _ | .callEmpty _ => false

end Belay.Sqlite
