import Belay.Sqlite.Resolution.QueryExprs

set_option doc.verso true

/-! Resolution of the {lit}`RETURNING` columns of an INSERT or UPDATE (ADR 0012,
slice 3a). SQLite resolves them as the result columns of a {lit}`SELECT` over the
written table, after the values and the filter: {lit}`*` is every column under its
defined name, an expression is evaluated over the written row and named by its
alias, the defined name of a bare column, or its source text. An aggregate is
SQLite's {lit}`misuse of aggregate function`. -/

namespace Belay.Sqlite

/-- The defined name of the column that a bare result expression names, as SQLite names
a result column without an alias: the column's name as declared, for an unqualified name
that reads one column ({name}`Scope.resolveName`) or a qualified name; none for any other
expression, such as a merged name of a full join, which SQLite names as written. -/
def definedName (scope : Scope) : Syntax.Expr → Option String
  | .identifier name _ => match scope.resolveName name with
    | .found _ [position] => scope.columns[position]?.map CatalogColumn.name
    | .found .. | .missing | .ambiguous => none
  | .qualified source column => (scope.qualified source column).bind (scope.columns[·]?.map CatalogColumn.name)
  | .null | .numeric _ | .string _ | .blob _ | .currentTime _ | .negate _ | .positive _ | .equals ..
  | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .callStar _ | .callEmpty _ | .call .. | .arithmetic ..
  | .cast .. | .callPair .. | .more .. => none

/-- One {lit}`RETURNING` column at position {lit}`item`: the expressions and names it
gives. The paths of its issues start at the column's position. A {lit}`source.*`
column is SQLite's {name}`PrepareError.returningSourceStar`. -/
def returningColumn (dqs : Bool) (scope : Scope) (item : Nat) :
    Syntax.ResultColumn → Except ValueIssue (List (Resolved.Expr × String))
  | .star => .ok (scope.visible.map fun (position, column) => ((scope.starOperand position column).1, column.name))
  | .sourceStar _ => .error (.prepare .returningSourceStar)
  | .expression value alias text => do
      let (resolved, _) ← (resolveOperand dqs scope true value).mapError (·.under [item, 0])
      .ok [(resolved, alias.getD ((definedName scope value).getD text))]

/-- Whether a result column is {lit}`source.*`. -/
def Syntax.ResultColumn.isSourceStar : Syntax.ResultColumn → Bool
  | .sourceStar _ => true
  | .star | .expression .. => false

/-- The {lit}`RETURNING` columns of a write over the table's scope, in order, or the
first issue. No {lit}`RETURNING` is the empty list. SQLite expands the wildcards before
it resolves names, so a {lit}`source.*` column anywhere is
{name}`PrepareError.returningSourceStar` before the issue of any other column. -/
def resolveReturning (dqs : Bool) (scope : Scope) (items : List Syntax.ResultColumn) :
    Except ValueIssue (List (Resolved.Expr × String)) :=
  if items.any Syntax.ResultColumn.isSourceStar then .error (.prepare .returningSourceStar) else
  (items.mapIdx fun item column => returningColumn dqs scope item column).foldr
    (fun next rest => do let first ← next; let others ← rest; .ok (first ++ others)) (.ok [])

end Belay.Sqlite
