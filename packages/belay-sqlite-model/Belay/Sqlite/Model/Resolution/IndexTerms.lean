import Belay.Sqlite.Model.Resolution.QueryExprs
import Belay.Sqlite.Model.Resolution.ParameterOrder
import Belay.Sqlite.Model.Resolution.NondeterministicCalls

set_option doc.verso true

/-! The key terms and the filter of CREATE INDEX (ADR 0014, D1). A term that is a column
name is a column key; any other term is an expression over the indexed table's row. The
prepare errors follow SQLite's {lit}`sqlite3CreateIndex` and {lit}`sqlite3ResolveSelfReference`,
checked natively with 3.51.0: the terms first, then the filter. -/

namespace Belay.Sqlite.Model

/-- The issue of a resolved key term or filter, or none: a {lit}`CURRENT_TIME`,
{lit}`CURRENT_DATE` or {lit}`CURRENT_TIMESTAMP` is SQLite's
{name}`ExprError.nondeterministicIndex` (with {lit}`filter` for the filter); a date and
time function, or a JSON function or another function that can fail
({name}`Resolved.Expr.isFallibleCall`), is a model restriction. -/
def indexExpressionIssue (filter : Bool) (resolved : Resolved.Expr) : Option ValueIssue :=
  if resolved.any Resolved.Expr.isNow then some (.prepare (.nondeterministicIndex filter))
  else if resolved.any Resolved.Expr.isDateCall then some (.restriction [] .indexDateFunction)
  else if resolved.any Resolved.Expr.isFallibleCall then some (.restriction [] .indexJsonFunction)
  else none

/-- A key term as an expression over the scope of the indexed table: a parameter is
{name}`ExprError.parameterInIndex` in SQLite's order ({name}`prohibitParameter`); a qualified name is
{name}`ExprError.qualifiedIndexTerm`; a call of a function that is not deterministic is
{name}`ExprError.nondeterministicIndex` where SQLite's walk finds no other error
({name}`prohibitNondeterministic`); else the resolved operand
({name}`resolveOperand`, with aggregates as misuse) and its
{name}`indexExpressionIssue`. -/
def indexExpressionTerm (dqs : Bool) (scope : Scope) (expression : Syntax.Expr) : Except ValueIssue KeyTerm :=
  prohibitParameter dqs scope (.parameterInIndex false) expression >>= fun _ =>
  if expression.hasQualifiedName then .error (.prepare .qualifiedIndexTerm) else do
    prohibitNondeterministic dqs scope (.nondeterministicIndex false) expression
    let (resolved, _) ← resolveOperand dqs scope {} true expression
    match indexExpressionIssue false resolved with
    | some issue => .error issue
    | none => .ok (.expression resolved)

/-- One key term of CREATE INDEX over the table's columns. An identifier that names a
column is that column; an unquoted {lit}`TRUE` or {lit}`FALSE` is an expression; a
double-quoted name that is no column, under the profile's {lit}`DQS_DDL`, and a string
literal are {name}`RestrictionKind.indexStringTerm`; any other name is
{lit}`no such column`, also {lit}`rowid`. {lit}`x COLLATE c` is the term of {lit}`x`, then
{lit}`no such collation sequence: c` for a name that names no collation, as
{lit}`sqlite3CreateIndex` checks a term's names before its collation. Every other term is
{name}`indexExpressionTerm`. -/
def indexTerm (dqs : Bool) (scope : Scope) (columns : List CatalogColumn) : Syntax.Expr → Except ValueIssue KeyTerm
  | expression@(.identifier name quote) =>
    match columnPosition columns name with
    | some position => .ok (.column position)
    | none =>
      if quote == .none && booleanKeywordName name then indexExpressionTerm dqs scope expression
      else if quote == .double && dqs then .error (.restriction [] .indexStringTerm)
      else .error (.prepare (.noSuchColumn name))
  | .string _ => .error (.restriction [] .indexStringTerm)
  | .collate operand name => do
    let term ← indexTerm dqs scope columns operand
    if (Collation.named? name).isNone then .error (.prepare (.noSuchCollation name)) else .ok term
  | expression@.null | expression@(.numeric _) | expression@(.blob _) | expression@(.parameter _)
  | expression@(.currentTime _)
  | expression@(.qualified ..) | expression@(.negate _) | expression@(.positive _) | expression@(.compare ..)
  | expression@(.and ..) | expression@(.or ..) | expression@(.not _) | expression@(.isNull ..)
  | expression@(.callStar _) | expression@(.call ..) | expression@(.arithmetic ..) | expression@(.cast ..)
  | expression@(.exists _) | expression@(.inQuery ..) | expression@(.subquery _) | expression@(.inList ..)
  | expression@(.between ..) | expression@(.caseOf ..) | expression@(.concatenate ..) | expression@(.raise ..) =>
    indexExpressionTerm dqs scope expression

/-- The key terms of CREATE INDEX in order, with their sort orders and collations: an
explicit {lit}`COLLATE`, else the column's, else {lit}`BINARY`
({name}`Syntax.Expr.collationIn`); the path of an issue of term {lit}`item` is
{lit}`[item, 0]` within the term list. A list with no term is SQLite's syntax error
({name}`ExprError.emptyKeyList`); SQL text cannot give it, so only syntax built in Lean does. -/
def indexKeys (dqs : Bool) (scope : Scope) (columns : List CatalogColumn) (terms : List Syntax.OrderTerm) :
    Except ValueIssue (List IndexKey) :=
  if terms.isEmpty then .error (.prepare .emptyKeyList) else terms.zipIdx.mapM fun (term, item) =>
    ((fun resolved => { term := resolved, descending := term.descending,
                        collation := term.expression.collationIn scope }) <$>
      indexTerm dqs scope columns term.expression).mapError (·.under [item, 0])

/-- The filter of a partial index as a condition over the scope of the indexed table, or
none: a parameter is {name}`ExprError.parameterInIndex` with {lit}`filter` in SQLite's order, aggregates are
misuse, a call of a function that is not deterministic is {name}`ExprError.nondeterministicIndex` with
{lit}`filter` ({name}`prohibitNondeterministic`), and the resolved condition has its {name}`indexExpressionIssue`. -/
def indexFilter (dqs : Bool) (scope : Scope) : Option Syntax.Expr → Except ValueIssue (Option Resolved.Expr)
  | none => .ok none
  | some term => do
    prohibitParameter dqs scope (.parameterInIndex true) term
    prohibitNondeterministic dqs scope (.nondeterministicIndex true) term
    let resolved ← condition [] (resolveOperand dqs scope {} true term)
    match indexExpressionIssue true resolved with
    | some issue => .error issue
    | none => .ok (some resolved)

end Belay.Sqlite.Model
