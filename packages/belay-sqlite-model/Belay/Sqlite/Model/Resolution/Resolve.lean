import Belay.Sqlite.Model.Resolution.SelectResolution
import Belay.Sqlite.Model.Resolution.WriteResolution
import Belay.Sqlite.Model.Resolution.StatementCatalog
import Belay.Sqlite.Model.Resolution.Updates
import Belay.Sqlite.Model.Resolution.Deletes
import Belay.Sqlite.Model.Resolution.Drops
import Belay.Sqlite.Model.Resolution.ResolveState
import Belay.Sqlite.Model.Resolution.TriggerDefinitions
import Belay.Sqlite.Model.Resolution.PragmaResolution

set_option doc.verso true

/-! Name resolution of a script. Each statement is resolved against the catalog
that the earlier statements leave when they succeed. BEGIN saves the catalog,
ROLLBACK restores it and COMMIT drops the saved copy. Resolution also follows the
setting of {lit}`PRAGMA foreign_keys`, which no ROLLBACK undoes, and gives each write the
foreign keys that it must check (ADR 0018, D4). A statement after a prepare
error is resolved as if that statement had no effect: SQLite never runs it, and a
model restriction there still refuses the script, which is conservative. -/

namespace Belay.Sqlite.Model

/-- Resolve one statement against the state, with no statement index: a restriction is one
inside the statement ({name}`NodeRestriction`). BEGIN in an open transaction and
COMMIT or ROLLBACK without one fail when SQLite runs them, not when it prepares
them, so they resolve and leave the error to the execution semantics: such a BEGIN
keeps the first saved catalog, and such a ROLLBACK keeps the current catalog.
A pragma resolves with {name}`resolvePragma`: {lit}`PRAGMA foreign_keys = value` changes the
state's setting outside a transaction and nothing inside one, as SQLite does, and
{lit}`PRAGMA recursive_triggers = value` changes it also inside one. -/
def resolveStatement (context : ResolveContext) (state : ResolveState) :
    Syntax.Statement → Except NodeRestriction (Resolved.Statement × ResolveState)
  | .begin => .ok (.begin, { state with saved := state.saved.getD state.catalog })
  | .commit => .ok (.commit, { state with saved := none })
  | .rollback => .ok (.rollback, { state with catalog := state.saved.getD state.catalog, saved := none })
  | .pragma pragma => resolvePragma state pragma
  | .createTable name columns constraints options =>
    state.withCatalog (resolveCreateTable context state.catalog name columns constraints options)
  | .createIndex name unique table terms filter =>
    state.withCatalog (resolveCreateIndex context state.catalog name unique table terms filter)
  | .addColumn table column => state.withCatalog (resolveAddColumn context state.catalog table column)
  | .dropTable name ifExists => state.withWrite context (resolveDropTable state.catalog name ifExists)
  | .dropIndex name ifExists => state.withCatalog (resolveDropIndex state.catalog name ifExists)
  | .createTrigger name ifNotExists time event table condition body =>
    state.withCatalog (resolveCreateTrigger state.catalog name ifNotExists { table, time, event, condition, body })
  | .dropTrigger name ifExists => state.withCatalog (resolveDropTrigger state.catalog name ifExists)
  | .insert table columns rows conflicts algorithm returning subqueries =>
    state.withWrite context (resolveWriteSubqueries context state.catalog 6 table (fun _ => []) subqueries
      (resolveInsert context state.catalog table columns rows conflicts algorithm returning))
  | .update table assignments filter returning subqueries =>
    state.withWrite context (resolveWriteSubqueries context state.catalog 4 table (writtenScope table) subqueries
      (resolveUpdate context state.catalog table assignments filter returning))
  | .select columns source joins filter groupBy orderBy limit offset subqueries having distinct compound =>
    state.withCatalog (resolveSelect context state.catalog
      { columns, source, joins, filter, groupBy, orderBy, limit, offset, parent := none, having, distinct, compound }
      subqueries)
  | .delete table filter returning subqueries =>
    state.withWrite context (resolveWriteSubqueries context state.catalog 3 table (writtenScope table) subqueries
      (resolveDelete context state.catalog table filter returning))

/-- Resolve the statements from a zero-based index and a state, in order. A restriction of a
statement gets the statement's index ({name}`NodeRestriction.at`). -/
def resolveFrom (context : ResolveContext) (index : Nat) (state : ResolveState) :
    List Syntax.Statement → Except Restriction (List Resolved.Statement × ResolveState)
  | [] => .ok ([], state)
  | statement :: rest =>
    match resolveStatement context state statement with
    | .error restriction => .error (restriction.at index)
    | .ok (resolved, next) => do
      let (later, final) ← resolveFrom context (index + 1) next rest
      return (resolved :: later, final)

/-- Resolve a script against a starting catalog, from index zero outside a
transaction, with foreign keys on when the profile turns them on. The result has one
resolved statement or prepare error for each
statement, and the catalog after all of them succeed; or the first model
restriction. -/
def resolve (context : ResolveContext) (catalog : Catalog) (script : List Syntax.Statement) :
    ResolveResult :=
  match resolveFrom context 0 (ResolveState.initial context.profile catalog) script with
  | .ok (statements, state) => .resolved statements state.catalog
  | .error restriction => .restricted restriction

end Belay.Sqlite.Model
