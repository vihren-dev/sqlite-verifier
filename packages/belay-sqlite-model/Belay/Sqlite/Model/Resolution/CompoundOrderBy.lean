import Belay.Sqlite.Model.Resolution.CompoundTerms

set_option doc.verso true

/-! The {lit}`ORDER BY` of a compound {lit}`SELECT` (ADR 0019, D3; {lit}`resolveCompoundOrderBy`
of {lit}`resolve.c`). Each term names a result column: by a column number, else on each term of
the compound from the left, by an {lit}`AS` alias of that term, then as an expression equal to a
result expression of that term. The match reads the term without its outer {lit}`COLLATE`, and
the sort uses that {lit}`COLLATE`. Paths are those of {lit}`Syntax.Subquery`: the {lit}`ORDER BY`
terms are child 5. -/

namespace Belay.Sqlite.Model

/-- A term of a compound as resolution has it when it resolves the compound's {lit}`ORDER BY`:
the scope of the term, its syntax, the resolved query and its shape. -/
structure CompoundTerm where
  /-- The scope of the term, enclosed by those of the queries around the compound. -/
  scope : Scope
  /-- The term as written. -/
  written : Syntax.Subquery
  /-- The resolved term. -/
  query : Resolved.Query
  /-- The shape of the resolved term. -/
  shape : SubqueryShape

/-- The column number of an {lit}`ORDER BY` term of a compound ({lit}`sqlite3ExprIsInteger`): an
integer literal from 0 to 2147483647, also in hexadecimal, under unary plus and minus, which
negates it; none for any other expression, such as {lit}`2147483648` or {lit}`1.0`. For example
{assert}`columnNumber (.negate (.numeric "1")) = some (-1)`. -/
def columnNumber : Syntax.Expr → Option Int
  | .numeric text => match numericValue text false with
    | .integer value => if 0 ≤ value ∧ value ≤ 2147483647 then some value else none
    | .real | .hexTooBig => none
  | .positive operand => columnNumber operand
  | .negate operand => (columnNumber operand).map (- ·)
  | .null | .string _ | .blob _ | .parameter _ | .currentTime _ | .identifier .. | .compare .. | .and .. | .or ..
  | .not _ | .isNull .. | .callStar _ | .call .. | .arithmetic .. | .cast .. | .qualified .. | .collate ..
  | .exists _ | .inQuery .. | .subquery _ | .inList .. | .between .. | .caseOf .. | .concatenate .. | .raise .. => none

/-- The expression without the {lit}`COLLATE` operators around it
({lit}`sqlite3ExprSkipCollate`), and whether each of their names names a collation. -/
def Syntax.Expr.withoutCollate : Syntax.Expr → Syntax.Expr × Bool
  | .collate operand name =>
    let (inner, known) := operand.withoutCollate
    (inner, known && (Collation.named? name).isSome)
  | expression@.null | expression@(.numeric _) | expression@(.string _) | expression@(.blob _)
  | expression@(.parameter _) | expression@(.currentTime _) | expression@(.identifier ..) | expression@(.negate _)
  | expression@(.positive _) | expression@(.compare ..) | expression@(.and ..) | expression@(.or ..)
  | expression@(.not _) | expression@(.isNull ..) | expression@(.callStar _) | expression@(.call ..)
  | expression@(.arithmetic ..) | expression@(.cast ..) | expression@(.qualified ..) | expression@(.exists _)
  | expression@(.inQuery ..) | expression@(.subquery _) | expression@(.inList ..) | expression@(.between ..)
  | expression@(.caseOf ..) | expression@(.concatenate ..) | expression@(.raise ..) => (expression, true)

/-- Whether an {lit}`ORDER BY` expression that resolves to the same expression as a result
expression of a term matches it as SQLite compares them ({lit}`sqlite3ExprCompare`): both read
one column by name, or a column of {lit}`*` (none as written), or the result expression without
its outer {lit}`COLLATE` is the same as written ({name}`Syntax.Expr.same`). -/
def sameAsWritten (resolved : Resolved.Expr) (written : Option Syntax.Expr) (expression : Syntax.Expr) : Bool :=
  let named := fun (value : Syntax.Expr) => value matches .identifier .. | .qualified ..
  (resolved matches .column _) && named expression && (written.all fun value => named value.withoutCollate.1) ||
    written.any fun value => value.withoutCollate.1.same expression

/-- The result column of one term that an {lit}`ORDER BY` expression without its outer
{lit}`COLLATE` names: the first column whose {lit}`AS` alias is the name; else the first
result expression equal to the expression resolved over the term's own sources only
({name}`Scope.inner`), which needs the same expression as written ({name}`sameAsWritten`), else
{name}`RestrictionKind.compoundOrderByTerm`. An expression that does not resolve there matches
no column. An aggregate is {name}`RestrictionKind.compoundOrderByTerm`, and a name of an alias
inside an expression {name}`RestrictionKind.aliasInExpression`. -/
def termMatch (dqs : Bool) (term : CompoundTerm) (expression : Syntax.Expr) : Except ValueIssue (Option Nat) :=
  let aliases := resultAliases term.scope term.written.columns
  let byAlias := match expression with
    | .identifier name _ => aliasIndex aliases name
    | .null | .numeric _ | .string _ | .blob _ | .parameter _ | .currentTime _ | .negate _ | .positive _
    | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .callStar _ | .call .. | .arithmetic .. | .cast ..
    | .qualified .. | .collate .. | .exists _ | .inQuery .. | .subquery _ | .inList .. | .between .. | .caseOf ..
    | .concatenate .. | .raise .. => none
  match byAlias with
  | some column => .ok (some column)
  | none =>
    if !expression.aggregateCalls.isEmpty then .error (.restriction [] .compoundOrderByTerm)
    else if namesAlias term.scope (aliases.filterMap id) expression then .error aliasInExpression
    else match resolveOperand dqs term.scope.inner {} false expression with
      | .error (.prepare _) => .ok none
      | .error issue@(.restriction ..) => .error issue
      | .ok (resolved, _) => match term.query.columns.findIdx? (· == .scalar resolved) with
        | none => .ok none
        | some column =>
          if sameAsWritten resolved ((resultExpressions term.scope term.written.columns).getD column none) expression
          then .ok (some column) else .error (.restriction [] .compoundOrderByTerm)

/-- The result column that an {lit}`ORDER BY` expression names on the first term from the left
where it matches one ({name}`termMatch`), or none. -/
def firstMatch (dqs : Bool) (terms : List CompoundTerm) (expression : Syntax.Expr) : Except ValueIssue (Option Nat) :=
  terms.foldlM (fun found term => match found with
    | some column => pure (some column)
    | none => termMatch dqs term expression) none

/-- The collation of an outer {lit}`COLLATE` of an expression, which a compound's sort uses
after SQLite replaces the matched expression by its column number; none without one. -/
def Syntax.Expr.outerCollation (expression : Syntax.Expr) : Option Collation :=
  match expression with
  | .collate .. => expression.explicitCollation
  | .null | .numeric _ | .string _ | .blob _ | .parameter _ | .currentTime _ | .identifier .. | .negate _ | .positive _
  | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .callStar _ | .call .. | .arithmetic .. | .cast ..
  | .qualified .. | .exists _ | .inQuery .. | .subquery _ | .inList .. | .between .. | .caseOf .. | .concatenate ..
  | .raise .. => none

/-- Resolve the {lit}`ORDER BY` of a compound over its terms, with its column collations: first
each column number, out of range as SQLite's {lit}`%r ORDER BY term out of range - should be
between 1 and %d`; then every other term on each term of the compound ({name}`firstMatch`), and
the first term that names no column is SQLite's
{lit}`%r ORDER BY term does not match any column in the result set`. A term sorts under its
outer {lit}`COLLATE` ({name}`Syntax.Expr.outerCollation`), else under the column's collation:
{lit}`columns` without the rewrite of SQLite, and {lit}`leftmost`, the collations of the
left-most term's expressions, when SQLite sorts the compound as {lit}`SELECT * FROM (compound)`
({lit}`derived`). An outer {lit}`COLLATE` with a name that names no collation is
{name}`RestrictionKind.unknownCollation`. -/
def resolveCompoundOrderBy (dqs : Bool) (terms : List CompoundTerm) (columns leftmost : List Collation) (derived : Bool)
    (orderBy : List Syntax.OrderTerm) : Except ValueIssue (List Resolved.SortTerm) := do
  let width := columns.length
  let numbers ← orderBy.zipIdx.mapM fun (term, item) => match term.expression.withoutCollate with
    | (_, false) => throw (.restriction [5, item] .unknownCollation)
    | (expression, true) => match columnNumber expression with
      | some number => if 1 ≤ number ∧ number ≤ width then pure (some (number.toNat - 1))
        else throw (.prepare (.orderByOutOfRange (item + 1) width))
      | none => pure none
  let matched ← (orderBy.zip numbers).zipIdx.mapM fun ((term, number), item) => match number with
    | some column => pure (some column)
    | none => (firstMatch dqs terms term.expression.withoutCollate.1).mapError (·.under [5, item, 0])
  let found ← (matched.zipIdx).mapM fun (column, item) => match column with
    | some column => pure column
    | none => throw (.prepare (.orderByNoMatch (item + 1)))
  pure ((orderBy.zip found).map fun (term, column) =>
    { key := .output column, descending := term.descending,
      collation := term.expression.outerCollation.getD ((if derived then leftmost else columns).getD column .binary) })

end Belay.Sqlite.Model
