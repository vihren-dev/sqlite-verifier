import Belay.Sqlite.Model.Resolution.CompoundOrderBy
import Belay.Sqlite.Model.Resolution.CompoundNames

set_option doc.verso true

/-! Resolution of a compound {lit}`SELECT` from its resolved terms (ADR 0019, D3): its columns,
their collations, its {lit}`ORDER BY` and its window, and its shape as a subquery. SQLite resolves
the terms from right to left and checks the number of columns of a term against the term on its
right after the names of that term; the compound's {lit}`ORDER BY` comes last. -/

namespace Belay.Sqlite.Model

/-- SQLite's error when term {lit}`index` of a compound and the term on its right have a
different number of result columns, after the names of term {lit}`index`
({lit}`SELECTs to the left and right of %s do not have the same number of result columns`, with
the operator between them): {lit}`width` is the number of columns of term {lit}`index`, and
{lit}`later` the shapes of the subqueries from {lit}`base` on. None when the numbers are the same
or the index is no term with a term on its right. -/
def compoundColumnsIssue (compound : Option Syntax.Compound) (index width base : Nat) (later : List SubqueryShape) :
    Option ValueIssue :=
  (compound.bind (·.rightOf index)).bind fun (operator, right) =>
    if (later[right - base]?.map (·.columns)) == some width then none else some (.prepare (.compoundColumns operator))

/-- The terms of a compound whose parent is {lit}`parent`, from left to right
({name}`CompoundTerm`), from the scopes and the syntax of the statement's subqueries and the
resolved queries and shapes of the subqueries from {lit}`base` on; else
{name}`RestrictionKind.subqueryHere`, which the frontend never gives. -/
def compoundTerms (base : Nat) (parent : Option Nat) (compound : Syntax.Compound) (scopes : List Scope)
    (subqueries : List Syntax.Subquery) (queries : List Resolved.Query) (shapes : List SubqueryShape) :
    Except ValueIssue (List CompoundTerm) :=
  compound.terms.mapM fun index =>
    let term : Option CompoundTerm := do
      let written ← subqueries[index]?
      if base ≤ index && written.parent == parent then
        pure { scope := ← scopes[index]?, written, query := ← queries[index - base]?, shape := ← shapes[index - base]? }
      else none
    match term with
    | some term => .ok term
    | none => .error (.restriction [] .subqueryHere)

/-- Whether SQLite sorts a compound as {lit}`SELECT * FROM (compound)`
({lit}`convertCompoundSelectToSubquery`): an operator is not {lit}`UNION ALL` and an
{lit}`ORDER BY` term has a {lit}`COLLATE`. -/
def sortsAsDerived (compound : Syntax.Compound) (orderBy : List Syntax.OrderTerm) : Bool :=
  compound.rest.any (fun (operator, _) => operator != .unionAll) && orderBy.any (·.expression.explicitCollation.isSome)

/-- Whether a compound query as written has no clause of its own besides {lit}`ORDER BY`,
{lit}`LIMIT` and {lit}`OFFSET`, as the frontend writes it. -/
def Syntax.Subquery.compoundForm (query : Syntax.Subquery) : Bool :=
  query.columns.isEmpty && query.source.isNone && query.joins.isEmpty && query.filter.isNone &&
    query.groupBy.isEmpty && query.having.isNone && !query.distinct

/-- Resolve a compound query from its resolved terms, from left to right, with {lit}`outer`
cells of the queries around it: a query without sources or columns of its own whose
{name}`Resolved.Query.compound` names the terms, with the names of the left-most term, or of
the derived table's columns ({name}`derivedNames`) when SQLite sorts it as
{lit}`SELECT * FROM (compound)` ({name}`sortsAsDerived`), the
column collations of {name}`compoundCollations`, the {lit}`ORDER BY` of
{name}`resolveCompoundOrderBy` and the window of a single {lit}`SELECT`; and its shape as a
subquery. The shape has the number of columns, the affinity and the collations of the first
column of the right-most term, which {lit}`IN` and a scalar subquery read, and the lowest cell
that a term reads. A compound with another clause of its own, or without terms, is
{name}`RestrictionKind.subqueryHere`, which the frontend never gives. -/
def resolveCompoundBody (dqs : Bool) (outer : Nat) (query : Syntax.Subquery) (compound : Syntax.Compound)
    (terms : List CompoundTerm) : Except ValueIssue (Resolved.Query × SubqueryShape) := do
  let (some first, some last) := (terms.head?, terms.getLast?) | throw (.restriction [] .subqueryHere)
  if !query.compoundForm then throw (.restriction [] .subqueryHere)
  let width := first.query.columns.length
  let collations := compoundCollations (terms.map fun term => optionalCollations term.scope term.written.columns) width
  let derived := sortsAsDerived compound query.orderBy
  let names ← if !derived then pure first.query.names else
    match derivedNames first.scope first.written.columns first.query.names with
    | some names => pure names
    | none => throw (.restriction [5] .compoundOrderByTerm)
  let order ← resolveCompoundOrderBy dqs terms collations (resultCollations first.scope first.written.columns) derived
    query.orderBy
  let (limitValue, limitParameter) ← windowValue [6] query.limit
  let (offsetValue, offsetParameter) ← windowValue [7] query.offset
  if offsetValue.any (· < 0) then throw (.restriction [7] .negativeOffset)
  let resolved : Resolved.Query :=
    { sources := [], filter := none, aggregate := false, groupBy := [], columns := [], names,
      orderBy := order, offset := (offsetValue.getD 0).toNat,
      limit := limitValue.bind fun value => if value < 0 then none else some value.toNat,
      limitParameter, offsetParameter, outer,
      compound := some { first := compound.first, rest := compound.rest, collations } }
  let shape : SubqueryShape :=
    { parent := query.parent, columns := width, affinity := last.shape.affinity,
      explicitCollation := last.shape.explicitCollation, columnCollation := last.shape.columnCollation,
      lowest := terms.foldl (fun lowest term => minPosition lowest term.shape.lowest) none, derived }
  pure (resolved, shape)

end Belay.Sqlite.Model
