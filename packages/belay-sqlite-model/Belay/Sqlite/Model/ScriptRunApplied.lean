import Belay.Sqlite.Model.ResolveStatementApplied
import Belay.Sqlite.Model.AdmittedStatementKeeps
import Belay.Sqlite.Model.ScriptRun

set_option doc.verso true

/-! The condition "the catalog after the statement is valid" for a statement that {lit}`runScriptFrom`
resolves (ADR 0022, D3, slice 4). The state of the resolver is made from the state of the connection
({lit}`Connection.resolveState`): the catalog of its database and the catalog of its snapshot. So a connection
whose database and snapshot have a valid catalog has a valid resolution state, and the fact of the resolver
({lit}`resolveStatement_applyCatalog_valid`) gives the condition of the statement theorems of the Admitted
atoms. -/

namespace Belay.Sqlite.Model

/-- For every limits and connection: if the state of the connection satisfies {name}`SqlState.Holds` for
{name}`Database.CatalogSupported` (the catalog of its database, and of its snapshot when a transaction is open,
is valid under the limits), then its resolution state ({name}`Connection.resolveState`) is valid under the
limits ({name}`ResolveState.Valid`). Proof sketch: the resolution state has the catalog of the database and
the catalog of the snapshot. -/
theorem Connection.resolveState_valid {limits : Limits} {connection : Connection}
    (holds : connection.state.Holds (Database.CatalogSupported limits)) : connection.resolveState.Valid limits :=
  ⟨holds.1, fun saved same => by
    obtain ⟨snapshot, found, rfl⟩ := Option.map_eq_some_iff.mp same
    exact holds.2 snapshot found⟩

/-- For every context in execution mode with the limits, connection, statement and resolution: if the state of
the connection satisfies {name}`SqlState.Holds` for {name}`Database.CatalogSupported` under the limits and
{name}`resolveStatement` resolves the statement over the connection, the resolved statement meets
{name}`Resolved.Statement.AppliedValid` on the database of the connection: the catalog after it is valid under
the limits. Proof sketch: {name}`resolveStatement_applyCatalog_valid` for the resolution state, which is valid
({name}`Connection.resolveState_valid`) and has the catalog of the database. -/
theorem resolveStatement_appliedValid {limits : Limits} (context : ResolveContext)
    (execution : context.mode = .execution) (same : context.profile.limits = limits) {connection : Connection}
    (holds : connection.state.Holds (Database.CatalogSupported limits)) {statement : Syntax.Statement}
    {resolved : Resolved.Statement} {after : ResolveState}
    (ok : resolveStatement context connection.resolveState statement = .ok (resolved, after)) :
    resolved.AppliedValid limits connection.state.database := by
  subst same
  exact resolveStatement_applyCatalog_valid context connection.resolveState after statement resolved execution
    (connection.resolveState_valid holds) ok

end Belay.Sqlite.Model
