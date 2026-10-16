import Belay.Sqlite.Resolution.Queries
import Belay.Sqlite.Resolution.Updates
import Belay.Sqlite.Resolution.Deletes

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

/-- The path of a restriction of a write inside {lit}`Syntax.Statement.returning`: the
write's {lit}`RETURNING` columns (child 4 of the resolved write) are child 1 of the
wrapper, and every other part is inside the write, child 0. -/
def returningPath : List Nat → List Nat
  | 4 :: rest => 1 :: rest
  | path => 0 :: path

/-- A write's resolution with its restriction paths inside the {lit}`RETURNING` wrapper. -/
def returningPaths (resolution : StatementResolution) : StatementResolution :=
  resolution.mapError fun restriction => { restriction with path := returningPath restriction.path }

/-- For every resolution and result: if {name}`returningPaths` succeeds with the result,
the resolution succeeds with the same result. Proof sketch: only the error changes. -/
theorem returningPaths_ok (resolution : StatementResolution) (result : Resolved.Statement × Catalog)
    (ok : returningPaths resolution = .ok result) : resolution = .ok result := by
  cases resolution <;> simp_all [returningPaths, Except.mapError]

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
  | .insert table columns rows conflicts algorithm =>
    state.withCatalog (resolveInsert context state.catalog index table columns rows conflicts algorithm [])
  | .update table assignments filter =>
    state.withCatalog (resolveUpdate context state.catalog index table assignments filter [])
  | .select columns source joins filter groupBy orderBy limit offset =>
    state.withCatalog
      (resolveSelect context state.catalog index columns source joins filter groupBy orderBy limit offset)
  | .delete table filter => state.withCatalog (resolveDelete context state.catalog index table filter [])
  | .returning write columns => match write with
    | .insert table names rows conflicts algorithm =>
      state.withCatalog
        (returningPaths (resolveInsert context state.catalog index table names rows conflicts algorithm columns))
    | .update table assignments filter =>
      state.withCatalog (returningPaths (resolveUpdate context state.catalog index table assignments filter columns))
    | .delete table filter =>
      state.withCatalog (returningPaths (resolveDelete context state.catalog index table filter columns))

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
