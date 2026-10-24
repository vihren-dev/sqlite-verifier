import Belay.Sqlite.Model.Resolution.SelectResolution

set_option doc.verso true

/-! Declarative rules of {lit}`SELECT` resolution (ADR 0012, slice 1) and their
proofs. A column reference resolves by {name}`Belay.Sqlite.Model.columnPosition`, whose
rule is in the column specification of ADR 0008; the rules here are the ones that
queries add. -/

namespace Belay.Sqlite.Model

/-- For every list of result column aliases and every term that is not an
identifier: if the term is an integer literal {lit}`k` from 1 to the number of
result columns, it names result column {lit}`k - 1`; if it is an integer literal
outside that range, it names no column and is out of range (SQLite's
{lit}`ORDER BY` or {lit}`GROUP BY` term out of range). -/
theorem namedResult_integer (names : List (Option Identifier)) (term : Syntax.Expr) (number : Int)
    (notIdentifier : ∀ name doubleQuoted, term ≠ .identifier name doubleQuoted)
    (literal : integerLiteral term = some number) :
    namedResult names term =
      if 1 ≤ number ∧ number ≤ (names.length : Int) then some (.ok (number.toNat - 1)) else some (.error ()) := by
  cases term with
  | identifier name doubleQuoted => exact absurd rfl (notIdentifier name doubleQuoted)
  | _ => simp only [namedResult, literal, Option.map_some]; split <;> rfl

/-- For every context, catalog, list of subqueries and {lit}`SELECT` with at
most {name}`maximumJoinTables` sources whose first source is a table (no table-valued
function): when the catalog has no table with the folded name of the first table and that
name is not reserved for SQLite's own tables and names no eponymous table-valued function
({name}`eponymousName`), resolution gives SQLite's
{lit}`no such table: %s` and keeps the catalog. The source reference has no indexed query. -/
theorem resolveSelect_noSuchTable (context : ResolveContext) (catalog : Catalog)
    (query : Syntax.Subquery) (subqueries : List Syntax.Subquery) (source : Syntax.TableReference)
    (first : query.source = some source) (tables : query.joins.length + 1 ≤ maximumJoinTables)
    (namedSource : source.query = none) (arguments : source.arguments = none)
    (missing : catalog.findTable source.table = none) (application : reservedName source.table = false)
    (table : eponymousName source.table = false) :
    resolveSelect context catalog query subqueries = .ok (.prepareError (.noSuchTable source.table), catalog) := by
  have notMore : ¬ query.joins.length + 1 > maximumJoinTables := by omega
  simp [resolveSelect, resolveSources, first, resolveReference, namedSource, arguments, resolveTableReference, missing, application, table,
    notMore, Except.mapError, SourceIssue.under, issueResolution, prepareError, Functor.map, Except.map, bind, Except.bind]

end Belay.Sqlite.Model
