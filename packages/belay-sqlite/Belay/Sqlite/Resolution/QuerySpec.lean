import Belay.Sqlite.Resolution.Queries

set_option doc.verso true

/-! Declarative rules of {lit}`SELECT` resolution (ADR 0012, slice 1) and their
proofs. A column reference resolves by {name}`Belay.Sqlite.columnPosition`, whose
rule is in the column specification of ADR 0008; the rules here are the ones that
queries add. -/

namespace Belay.Sqlite

/-- For every list of result column aliases and every term that is not an
identifier: if the term is an integer literal {lit}`k` from 1 to the number of
result columns, it names result column {lit}`k - 1`; if it is an integer literal
outside that range, it names no column and is out of range (SQLite's
{lit}`ORDER BY` or {lit}`GROUP BY` term out of range). -/
theorem namedResult_integer (names : List (Option String)) (term : Syntax.Expr) (number : Int)
    (notIdentifier : ∀ name doubleQuoted, term ≠ .identifier name doubleQuoted)
    (literal : integerLiteral term = some number) :
    namedResult names term =
      if 1 ≤ number ∧ number ≤ (names.length : Int) then some (.ok (number.toNat - 1)) else some (.error ()) := by
  cases term with
  | identifier name doubleQuoted => exact absurd rfl (notIdentifier name doubleQuoted)
  | _ => simp only [namedResult, literal, Option.map_some]; split <;> rfl

/-- For every context, catalog, statement index and {lit}`SELECT` with at most
{name}`maximumJoinTables` sources, all of them tables (no table-valued function): when the
catalog has no table with the folded name of
the first table and that name is not reserved for SQLite's own tables, resolution gives
SQLite's {lit}`no such table: %s` and keeps the catalog. -/
theorem resolveSelect_noSuchTable (context : ResolveContext) (catalog : Catalog) (index : Nat)
    (results : List Syntax.ResultColumn) (source : Syntax.TableReference) (joins : List Syntax.Join)
    (filter : Option Syntax.Expr) (groupBy : List Syntax.Expr) (orderBy : List Syntax.OrderTerm)
    (limit offset : Option Syntax.Expr) (tables : joins.length + 1 ≤ maximumJoinTables)
    (table : source.arguments = none) (plain : joins.all (·.source.arguments.isNone) = true)
    (missing : catalog.findTable source.table = none) (application : reservedName source.table = false) :
    resolveSelect context catalog index results source joins filter groupBy orderBy limit offset =
      .ok (.prepareError (.noSuchTable source.table), catalog) := by
  have notMore : ¬ joins.length + 1 > maximumJoinTables := by omega
  simp [resolveSelect, resolveSources, splitSources_tables source joins table plain, resolveTables,
    resolveTableReference, missing, application, notMore, issueResolution, prepareError, bind, Except.bind]

end Belay.Sqlite
