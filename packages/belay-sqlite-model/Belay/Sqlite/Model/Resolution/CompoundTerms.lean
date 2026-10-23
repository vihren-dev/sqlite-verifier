import Belay.Sqlite.Model.Resolution.Queries

set_option doc.verso true

/-! The terms of a compound {lit}`SELECT` as resolution reads them (ADR 0019, D3): which
subqueries are the terms of a compound, the order in which SQLite finds their tables, the
column collations of the compound, and the errors of {lit}`*` that SQLite gives before it
resolves a name. -/

namespace Belay.Sqlite.Model

/-- The indexes of the terms of a compound as written, from left to right. -/
def Syntax.Compound.terms (compound : Syntax.Compound) : List Nat :=
  compound.first :: compound.rest.map (·.2)

/-- The operator and the term on the right of term {lit}`index` of a compound, or
{lean}`(none : Option (CompoundOperator × Nat))` for its right-most term and for an index that
is no term. -/
def Syntax.Compound.rightOf (compound : Syntax.Compound) (index : Nat) : Option (CompoundOperator × Nat) :=
  List.lookup index (compound.terms.zip compound.rest)

/-- The compound whose terms have the parent {lit}`parent` in the statement's list of
subqueries: {lit}`main`, the statement's compound, for {lean}`(none : Option Nat)`, else the
compound of that subquery; none when the parent is one {lit}`SELECT`. -/
def compoundOf (main : Option Syntax.Compound) (subqueries : List Syntax.Subquery) :
    Option Nat → Option Syntax.Compound
  | none => main
  | some parent => subqueries[parent]?.bind (·.compound)

/-- The subqueries under the query {lit}`node` (none for the statement's query), each before
the subqueries under it, in the order in which SQLite finds their tables
({lit}`sqlite3SelectExpand` walks each {lit}`SELECT` before the subqueries of its expressions):
in the order of the list, but the terms of a compound from the right-most term to the left-most
({lit}`pPrior`). The fuel bounds the depth; the frontend lists a subquery after the query
around it, so the depth is below the number of subqueries. -/
def scopeOrder (main : Option Syntax.Compound) (subqueries : List Syntax.Subquery) : Nat → Option Nat → List Nat
  | 0, _ => []
  | fuel + 1, node =>
    let children := (List.range subqueries.length).filter fun index => (subqueries[index]?.map (·.parent)) == some node
    let ordered := if (compoundOf main subqueries node).isSome then children.reverse else children
    ordered.flatMap fun child => child :: scopeOrder main subqueries fuel (some child)

/-- The error of SQLite's expansion of {lit}`*` and {lit}`x.*` in the result columns over the
scope of their query, which SQLite gives before it resolves a name ({lit}`selectExpander`):
{lit}`no tables specified` for {lit}`*` without {lit}`FROM`, {lit}`no such table: x` for
{lit}`x.*` when no source of the query has the name {lit}`x`. SQLite expands every column, and
the last error replaces the earlier ones. None when every column expands. -/
def starIssue (scope : Scope) (columns : List Syntax.ResultColumn) : Option ValueIssue :=
  columns.foldl (fun issue column => (match column with
    | .star => if scope.inner.isEmpty then some (.prepare .noTablesSpecified) else none
    | .sourceStar name => if (scope.starColumns? name).isSome then none else some (.prepare (.noSuchSource name))
    | .expression .. => none) <|> issue) none

/-- The collation of each result column of a term in the sense of {lit}`sqlite3ExprCollSeq`,
in the order of its outputs: a column of {lit}`*` or {lit}`x.*` has its column's collation, an
expression its explicit collation, else its column's ({name}`Syntax.Expr.columnCollation`),
else none. -/
def optionalCollations (scope : Scope) (results : List Syntax.ResultColumn) : List (Option Collation) :=
  results.flatMap fun
    | .star => scope.visible.map fun (_, column) => some column.collation
    | .sourceStar name => ((scope.starColumns? name).map (·.map fun (_, column) => some column.collation)).getD []
    | .expression value _ _ => [value.explicitCollation <|> value.columnCollation scope]

/-- The collation of each of the {lit}`width` columns of a compound, from the collations of its
terms from left to right ({name}`optionalCollations`): that of the left-most term whose column
has one, else {lit}`BINARY` ({lit}`multiSelectCollSeq`). For example, over a term without a
collation and a {lit}`NOCASE` term, the column is {lit}`NOCASE`:
{assert}`compoundCollations [[none], [some .nocase]] 1 = [.nocase]`. -/
def compoundCollations (terms : List (List (Option Collation))) (width : Nat) : List Collation :=
  (List.range width).map fun column => (terms.findSome? fun term => term.getD column none).getD .binary

/-- The expression of each result column of a term as written, in the order of its outputs:
none for each column of {lit}`*` and {lit}`x.*`. -/
def resultExpressions (scope : Scope) (results : List Syntax.ResultColumn) : List (Option Syntax.Expr) :=
  results.flatMap fun
    | .star => scope.visible.map fun _ => none
    | .sourceStar name => ((scope.starColumns? name).map (·.map fun _ => none)).getD []
    | .expression value _ _ => [some value]

end Belay.Sqlite.Model
