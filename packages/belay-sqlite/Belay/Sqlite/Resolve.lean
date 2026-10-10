import Belay.Sqlite.ResolveWrites

set_option doc.verso true

/-! Name resolution of a script. Each statement is resolved against the catalog
that the earlier statements leave when they succeed. BEGIN saves the catalog,
ROLLBACK restores it and COMMIT drops the saved copy. A statement after a prepare
error is resolved as if that statement had no effect: SQLite never runs it, and a
model restriction there still refuses the script, which is conservative. -/

namespace Belay.Sqlite

/-- The catalog during resolution and the catalog that the open transaction saved.
Omit {name}`ResolveState.saved` outside a transaction. -/
structure ResolveState where
  /-- The current catalog. -/
  catalog : Catalog
  /-- The catalog at BEGIN, while a transaction is open. -/
  saved : Option Catalog := none
  deriving Repr, DecidableEq

/-- The state after a statement that is not transaction control: the catalog after
the statement, and the same saved catalog. -/
def ResolveState.withCatalog (state : ResolveState) (result : StatementResolution) :
    Except Restriction (Resolved.Statement × ResolveState) :=
  result.map fun (statement, catalog) => (statement, { state with catalog := catalog })

/-- Resolve one statement at its zero-based index. BEGIN in an open transaction and
COMMIT or ROLLBACK without one fail when SQLite runs them, not when it prepares
them, so they resolve and leave the error to the execution semantics: such a BEGIN
keeps the first saved catalog, and such a ROLLBACK keeps the current catalog. -/
def resolveStatement (context : ResolveContext) (state : ResolveState) (index : Nat) :
    Syntax.Statement → Except Restriction (Resolved.Statement × ResolveState)
  | .begin => .ok (.begin, { state with saved := state.saved.getD state.catalog })
  | .commit => .ok (.commit, { state with saved := none })
  | .rollback => .ok (.rollback, { catalog := state.saved.getD state.catalog, saved := none })
  | .createTable name columns constraints =>
    state.withCatalog (resolveCreateTable context state.catalog index name columns constraints)
  | .createIndex name unique table columns =>
    state.withCatalog (resolveCreateIndex context state.catalog index name unique table columns)
  | .addColumn table column => state.withCatalog (resolveAddColumn context state.catalog index table column)
  | .insert table columns rows => state.withCatalog (resolveInsert context state.catalog index table columns rows)
  | .update table assignments filter =>
    state.withCatalog (resolveUpdate context state.catalog index table assignments filter)

/-- Resolve the statements from a zero-based index and a state, in order. -/
def resolveFrom (context : ResolveContext) (index : Nat) (state : ResolveState) :
    List Syntax.Statement → Except Restriction (List Resolved.Statement × ResolveState)
  | [] => .ok ([], state)
  | statement :: rest => do
    let (resolved, next) ← resolveStatement context state index statement
    let (later, final) ← resolveFrom context (index + 1) next rest
    return (resolved :: later, final)

/-- Resolve a script against a starting catalog, from index zero outside a
transaction. The result has one resolved statement or prepare error for each
statement, and the catalog after all of them succeed; or the first model
restriction. -/
def resolve (context : ResolveContext) (catalog : Catalog) (script : List Syntax.Statement) :
    ResolveResult :=
  match resolveFrom context 0 { catalog := catalog } script with
  | .ok (statements, state) => .resolved statements state.catalog
  | .error restriction => .restricted restriction

end Belay.Sqlite
