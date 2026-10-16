import Belay.Sqlite.Resolution.Writes

set_option doc.verso true

/-! Resolution of UPDATE (ADR 0012, amendment 1, "Resolved forms"): each {lit}`SET`
value is an expression over the table's columns, and the {lit}`WHERE` filter is a
condition, both resolved as in {lit}`SELECT`. A value that names no column folds to
the literal of its stored value. A value that reads the row may not assign a column of
a unique key: that is a model restriction. -/

namespace Belay.Sqlite

/-- Resolve UPDATE. Path 1 is the assignment list, path 2 the filter and path 4 the
{lit}`RETURNING` columns, which resolve last. The assignments resolve in order, then
the filter as a condition; then a column assigned twice is a model restriction. A
{lit}`SET` value that reads the row for a key column is the restriction
{name}`RestrictionKind.rowDependentKey` of its assignment. A table with a constraint
algorithm other than ABORT is {name}`RestrictionKind.constraintAlgorithmUpdate`, after
every other check. -/
def resolveUpdate (context : ResolveContext) (catalog : Catalog) (index : Nat) (tableName : String)
    (assignments : List (String × Syntax.Expr)) (filter : Option Syntax.Expr)
    (returning : List Syntax.ResultColumn) : StatementResolution :=
  let dqs := context.profile.dqsDml
  match catalog.findTable tableName with
  | none => prepareError catalog (.noSuchTable tableName)
  | some (position, table) =>
    let keys := catalog.uniqueKeys position table
    let scope := Scope.single tableName table.columns
    match resolveAll (resolveAssignment dqs scope keys.flatten) assignments with
    | .error issue => issueResolution catalog index [1] issue
    | .ok resolved =>
      let resolvedCondition : Except ValueIssue (Option Resolved.Expr) := match filter with
        | none => .ok none
        | some term => some <$> condition [] (resolveOperand dqs scope true term)
      match resolvedCondition with
      | .error issue => issueResolution catalog index [2] issue
      | .ok resolvedFilter =>
        let positions := resolved.map Prod.fst
        if positions.eraseDups.length != positions.length then
          restrict index [1] .updateColumnTwice
        else match resolveReturning dqs scope returning with
          | .error issue => issueResolution catalog index [4] issue
          | .ok columns =>
            if (catalog.keyAlgorithms position table).all (· == .abort) &&
                table.columns.all (·.notNullAlgorithm == .abort) then
              .ok (.update position resolved resolvedFilter keys columns, catalog)
            else restrict index [] .constraintAlgorithmUpdate

end Belay.Sqlite
