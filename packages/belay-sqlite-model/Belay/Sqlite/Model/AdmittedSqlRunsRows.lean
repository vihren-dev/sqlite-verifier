import Belay.Sqlite.Model.AdmittedStatementKeeps

set_option doc.verso true

/-! The run theorems of the atoms "rows wide", "rows stored" and "rows aliased", and of all seven atoms
together, for {lit}`runSqlFrom` and {lit}`runSql` (ADR 0022, D3, slice 4). The theorem of an atom lists the
atoms that its statement theorem needs (decision 2 of the status file). The script passes the support check
at every statement that the run reaches ({lit}`supportedSqlFrom`). -/

namespace Belay.Sqlite.Model

/-- The run theorem of "rows wide" for {name}`runSqlFrom`. For every position, script and state: if the
state satisfies {name}`SqlState.Holds` for {name}`Database.RowsWide` (its database, and its snapshot when a
transaction is open), and the script passes the support check at every statement that the run reaches
({name}`supportedSqlFrom`), the outcome of {name}`runSqlFrom` satisfies {name}`Outcome.Holds` for
{name}`Database.RowsWide`: the database of a success or a failure, and the persisted and the visible
database of a pending outcome. Proof sketch: {name}`runSqlFrom_holds_ready` for
{name}`rowsWide_statementKeeps`. -/
theorem runSqlFrom_rowsWide (position : Nat) (script : List (Resolved.Statement × List Value))
    {state : SqlState} (holds : state.Holds (Database.RowsWide))
    (supported : supportedSqlFrom position script state = true) :
    (runSqlFrom position script state).Holds (Database.RowsWide) :=
  runSqlFrom_holds_ready (rowsWide_statementKeeps) position script holds supported (RunConditionsWith.always _ _ _)

/-- The run theorem of "rows wide" for {name}`runSql`. For every script and database: if the database
satisfies {name}`Database.RowsWide`, and the script passes the support check at every statement that the run
reaches ({name}`supportedSqlFrom`), the outcome of {name}`runSql` satisfies {name}`Outcome.Holds` for
{name}`Database.RowsWide`. Proof sketch: {name}`runSql_holds_ready` for {name}`rowsWide_statementKeeps`. -/
theorem runSql_rowsWide (script : List (Resolved.Statement × List Value)) {database : Database}
    (holds : Database.RowsWide database) (supported : supportedSqlFrom 0 script { database } = true) :
    (runSql script database).Holds (Database.RowsWide) :=
  runSql_holds_ready (rowsWide_statementKeeps) script holds supported (RunConditionsWith.always _ _ _)


/-- The run theorem of "rows stored" for {name}`runSqlFrom`. It lists "rows wide" (decision 2 of the status
file). For every position, script and state: if the state satisfies {name}`SqlState.Holds` for
{name}`Database.RowsStoredWide` (its database, and its snapshot when a transaction is open), and the script
passes the support check at every statement that the run reaches ({name}`supportedSqlFrom`), the outcome of
{name}`runSqlFrom` satisfies {name}`Outcome.Holds` for {name}`Database.RowsStoredWide`: the database of a
success or a failure, and the persisted and the visible database of a pending outcome. Proof sketch:
{name}`runSqlFrom_holds_ready` for {name}`rowsStored_statementKeeps`. -/
theorem runSqlFrom_rowsStored (position : Nat) (script : List (Resolved.Statement × List Value))
    {state : SqlState} (holds : state.Holds (Database.RowsStoredWide))
    (supported : supportedSqlFrom position script state = true) :
    (runSqlFrom position script state).Holds (Database.RowsStoredWide) :=
  runSqlFrom_holds_ready (rowsStored_statementKeeps) position script holds supported (RunConditionsWith.always _ _ _)

/-- The run theorem of "rows stored" for {name}`runSql`. It lists "rows wide" (decision 2 of the status
file). For every script and database: if the database satisfies {name}`Database.RowsStoredWide`, and the
script passes the support check at every statement that the run reaches ({name}`supportedSqlFrom`), the
outcome of {name}`runSql` satisfies {name}`Outcome.Holds` for {name}`Database.RowsStoredWide`. Proof sketch:
{name}`runSql_holds_ready` for {name}`rowsStored_statementKeeps`. -/
theorem runSql_rowsStored (script : List (Resolved.Statement × List Value)) {database : Database}
    (holds : Database.RowsStoredWide database) (supported : supportedSqlFrom 0 script { database } = true) :
    (runSql script database).Holds (Database.RowsStoredWide) :=
  runSql_holds_ready (rowsStored_statementKeeps) script holds supported (RunConditionsWith.always _ _ _)


/-- The run theorem of "rows aliased" for {name}`runSqlFrom`. It lists "catalog supported" (decision 2 of
the status file). For every limits, position, script and state: if the state satisfies
{name}`SqlState.Holds` for {name}`Database.RowsAliasedSupported` (its database, and its snapshot when a
transaction is open), and the script passes the support check at every statement that the run reaches
({name}`supportedSqlFrom`) and meets {name}`RunConditionsWith` for {name}`Resolved.Statement.AppliedValid`
(the catalog after each statement that the run reaches is valid under the limits) from the position and the
state, the outcome of {name}`runSqlFrom` satisfies {name}`Outcome.Holds` for
{name}`Database.RowsAliasedSupported`: the database of a success or a failure, and the persisted and the
visible database of a pending outcome. Proof sketch: {name}`runSqlFrom_holds_ready` for
{name}`rowsAliased_statementKeeps`. -/
theorem runSqlFrom_rowsAliased (limits : Limits) (position : Nat) (script : List (Resolved.Statement × List Value))
    {state : SqlState} (holds : state.Holds (Database.RowsAliasedSupported limits))
    (supported : supportedSqlFrom position script state = true)
    (conditions : RunConditionsWith (Resolved.Statement.AppliedValid limits) position script state) :
    (runSqlFrom position script state).Holds (Database.RowsAliasedSupported limits) :=
  runSqlFrom_holds_ready (rowsAliased_statementKeeps limits) position script holds supported conditions

/-- The run theorem of "rows aliased" for {name}`runSql`. It lists "catalog supported" (decision 2 of the
status file). For every limits, script and database: if the database satisfies
{name}`Database.RowsAliasedSupported`, and the script passes the support check at every statement that the
run reaches ({name}`supportedSqlFrom`) and meets {name}`RunConditionsWith` for
{name}`Resolved.Statement.AppliedValid` (the catalog after each statement that the run reaches is valid
under the limits) from position 0 and the state of the database outside a transaction, the outcome of
{name}`runSql` satisfies {name}`Outcome.Holds` for {name}`Database.RowsAliasedSupported`. Proof sketch:
{name}`runSql_holds_ready` for {name}`rowsAliased_statementKeeps`. -/
theorem runSql_rowsAliased (limits : Limits) (script : List (Resolved.Statement × List Value)) {database : Database}
    (holds : Database.RowsAliasedSupported limits database) (supported : supportedSqlFrom 0 script { database } = true)
    (conditions : RunConditionsWith (Resolved.Statement.AppliedValid limits) 0 script { database }) :
    (runSql script database).Holds (Database.RowsAliasedSupported limits) :=
  runSql_holds_ready (rowsAliased_statementKeeps limits) script holds supported conditions


/-- The run theorem of "all seven atoms" for {name}`runSqlFrom`. It is the conjunction of the seven atoms.
For every profile, position, script and state: if the state satisfies {name}`SqlState.Holds` for
{name}`Database.Admitted` (its database, and its snapshot when a transaction is open), and the script passes
the support check at every statement that the run reaches ({name}`supportedSqlFrom`) and meets
{name}`RunConditionsWith` for {name}`Resolved.Statement.AppliedValid` (the catalog after each statement that
the run reaches is valid under the limits) from the position and the state, the outcome of
{name}`runSqlFrom` satisfies {name}`Outcome.Holds` for {name}`Database.Admitted`: the database of a success
or a failure, and the persisted and the visible database of a pending outcome. Proof sketch:
{name}`runSqlFrom_holds_ready` for {name}`admitted_statementKeeps`. -/
theorem runSqlFrom_admitted {profile : Profile} (position : Nat) (script : List (Resolved.Statement × List Value))
    {state : SqlState} (holds : state.Holds (Database.Admitted profile))
    (supported : supportedSqlFrom position script state = true)
    (conditions : RunConditionsWith (Resolved.Statement.AppliedValid profile.limits) position script state) :
    (runSqlFrom position script state).Holds (Database.Admitted profile) :=
  runSqlFrom_holds_ready (admitted_statementKeeps profile) position script holds supported conditions

/-- The run theorem of "all seven atoms" for {name}`runSql`. It is the conjunction of the seven atoms. For
every profile, script and database: if the database satisfies {name}`Database.Admitted`, and the script
passes the support check at every statement that the run reaches ({name}`supportedSqlFrom`) and meets
{name}`RunConditionsWith` for {name}`Resolved.Statement.AppliedValid` (the catalog after each statement that
the run reaches is valid under the limits) from position 0 and the state of the database outside a
transaction, the outcome of {name}`runSql` satisfies {name}`Outcome.Holds` for {name}`Database.Admitted`.
Proof sketch: {name}`runSql_holds_ready` for {name}`admitted_statementKeeps`. -/
theorem runSql_admitted {profile : Profile} (script : List (Resolved.Statement × List Value)) {database : Database}
    (holds : Database.Admitted profile database) (supported : supportedSqlFrom 0 script { database } = true)
    (conditions : RunConditionsWith (Resolved.Statement.AppliedValid profile.limits) 0 script { database }) :
    (runSql script database).Holds (Database.Admitted profile) :=
  runSql_holds_ready (admitted_statementKeeps profile) script holds supported conditions


end Belay.Sqlite.Model
