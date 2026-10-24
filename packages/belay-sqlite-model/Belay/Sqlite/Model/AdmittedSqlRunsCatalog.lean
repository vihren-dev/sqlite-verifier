import Belay.Sqlite.Model.AdmittedStatementKeeps

set_option doc.verso true

/-! The run theorems of the atoms "catalog supported", "rows shaped", "rowids distinct" and "rowids in range"
for {lit}`runSqlFrom` and {lit}`runSql` (ADR 0022, D3, slice 4): a run from a state whose database and
snapshot have the atom gives an outcome whose databases have it. The script passes the support check at
every statement that the run reaches ({lit}`supportedSqlFrom`), and, for "catalog supported", the catalog
after each statement is valid. They are the run theorems of {lit}`RunHoldsReady` for the statement theorems
of {lit}`AdmittedStatementKeeps`. -/

namespace Belay.Sqlite.Model

/-- The run theorem of "catalog supported" for {name}`runSqlFrom`. For every limits, position, script and
state: if the state satisfies {name}`SqlState.Holds` for {name}`Database.CatalogSupported` (its database,
and its snapshot when a transaction is open), and the script passes the support check at every statement
that the run reaches ({name}`supportedSqlFrom`) and meets {name}`RunConditionsWith` for
{name}`Resolved.Statement.AppliedValid` (the catalog after each statement that the run reaches is valid
under the limits) from the position and the state, the outcome of {name}`runSqlFrom` satisfies
{name}`Outcome.Holds` for {name}`Database.CatalogSupported`: the database of a success or a failure, and the
persisted and the visible database of a pending outcome. Proof sketch: {name}`runSqlFrom_holds_ready` for
{name}`catalogSupported_statementKeeps`. -/
theorem runSqlFrom_catalogSupported (limits : Limits) (position : Nat) (script : List (Resolved.Statement × List Value))
    {state : SqlState} (holds : state.Holds (Database.CatalogSupported limits))
    (supported : supportedSqlFrom position script state = true)
    (conditions : RunConditionsWith (Resolved.Statement.AppliedValid limits) position script state) :
    (runSqlFrom position script state).Holds (Database.CatalogSupported limits) :=
  runSqlFrom_holds_ready (catalogSupported_statementKeeps limits) position script holds supported conditions

/-- The run theorem of "catalog supported" for {name}`runSql`. For every limits, script and database: if the
database satisfies {name}`Database.CatalogSupported`, and the script passes the support check at every
statement that the run reaches ({name}`supportedSqlFrom`) and meets {name}`RunConditionsWith` for
{name}`Resolved.Statement.AppliedValid` (the catalog after each statement that the run reaches is valid
under the limits) from position 0 and the state of the database outside a transaction, the outcome of
{name}`runSql` satisfies {name}`Outcome.Holds` for {name}`Database.CatalogSupported`. Proof sketch:
{name}`runSql_holds_ready` for {name}`catalogSupported_statementKeeps`. -/
theorem runSql_catalogSupported (limits : Limits) (script : List (Resolved.Statement × List Value)) {database : Database}
    (holds : Database.CatalogSupported limits database) (supported : supportedSqlFrom 0 script { database } = true)
    (conditions : RunConditionsWith (Resolved.Statement.AppliedValid limits) 0 script { database }) :
    (runSql script database).Holds (Database.CatalogSupported limits) :=
  runSql_holds_ready (catalogSupported_statementKeeps limits) script holds supported conditions


/-- The run theorem of "rows shaped" for {name}`runSqlFrom`. For every position, script and state: if the
state satisfies {name}`SqlState.Holds` for {name}`Database.RowsShaped` (its database, and its snapshot when
a transaction is open), and the script passes the support check at every statement that the run reaches
({name}`supportedSqlFrom`), the outcome of {name}`runSqlFrom` satisfies {name}`Outcome.Holds` for
{name}`Database.RowsShaped`: the database of a success or a failure, and the persisted and the visible
database of a pending outcome. Proof sketch: {name}`runSqlFrom_holds_ready` for
{name}`rowsShaped_statementKeeps`. -/
theorem runSqlFrom_rowsShaped (position : Nat) (script : List (Resolved.Statement × List Value))
    {state : SqlState} (holds : state.Holds (Database.RowsShaped))
    (supported : supportedSqlFrom position script state = true) :
    (runSqlFrom position script state).Holds (Database.RowsShaped) :=
  runSqlFrom_holds_ready (rowsShaped_statementKeeps) position script holds supported (RunConditionsWith.always _ _ _)

/-- The run theorem of "rows shaped" for {name}`runSql`. For every script and database: if the database
satisfies {name}`Database.RowsShaped`, and the script passes the support check at every statement that the
run reaches ({name}`supportedSqlFrom`), the outcome of {name}`runSql` satisfies {name}`Outcome.Holds` for
{name}`Database.RowsShaped`. Proof sketch: {name}`runSql_holds_ready` for {name}`rowsShaped_statementKeeps`.
-/
theorem runSql_rowsShaped (script : List (Resolved.Statement × List Value)) {database : Database}
    (holds : Database.RowsShaped database) (supported : supportedSqlFrom 0 script { database } = true) :
    (runSql script database).Holds (Database.RowsShaped) :=
  runSql_holds_ready (rowsShaped_statementKeeps) script holds supported (RunConditionsWith.always _ _ _)


/-- The run theorem of "rowids distinct" for {name}`runSqlFrom`. For every position, script and state: if
the state satisfies {name}`SqlState.Holds` for {name}`Database.RowidsDistinct` (its database, and its
snapshot when a transaction is open), and the script passes the support check at every statement that the
run reaches ({name}`supportedSqlFrom`), the outcome of {name}`runSqlFrom` satisfies {name}`Outcome.Holds`
for {name}`Database.RowidsDistinct`: the database of a success or a failure, and the persisted and the
visible database of a pending outcome. Proof sketch: {name}`runSqlFrom_holds_ready` for
{name}`rowidsDistinct_statementKeeps`. -/
theorem runSqlFrom_rowidsDistinct (position : Nat) (script : List (Resolved.Statement × List Value))
    {state : SqlState} (holds : state.Holds (Database.RowidsDistinct))
    (supported : supportedSqlFrom position script state = true) :
    (runSqlFrom position script state).Holds (Database.RowidsDistinct) :=
  runSqlFrom_holds_ready (rowidsDistinct_statementKeeps) position script holds supported (RunConditionsWith.always _ _ _)

/-- The run theorem of "rowids distinct" for {name}`runSql`. For every script and database: if the database
satisfies {name}`Database.RowidsDistinct`, and the script passes the support check at every statement that
the run reaches ({name}`supportedSqlFrom`), the outcome of {name}`runSql` satisfies {name}`Outcome.Holds`
for {name}`Database.RowidsDistinct`. Proof sketch: {name}`runSql_holds_ready` for
{name}`rowidsDistinct_statementKeeps`. -/
theorem runSql_rowidsDistinct (script : List (Resolved.Statement × List Value)) {database : Database}
    (holds : Database.RowidsDistinct database) (supported : supportedSqlFrom 0 script { database } = true) :
    (runSql script database).Holds (Database.RowidsDistinct) :=
  runSql_holds_ready (rowidsDistinct_statementKeeps) script holds supported (RunConditionsWith.always _ _ _)


/-- The run theorem of "rowids in range" for {name}`runSqlFrom`. For every position, script and state: if
the state satisfies {name}`SqlState.Holds` for {name}`Database.RowidsInRange` (its database, and its
snapshot when a transaction is open), and the script passes the support check at every statement that the
run reaches ({name}`supportedSqlFrom`), the outcome of {name}`runSqlFrom` satisfies {name}`Outcome.Holds`
for {name}`Database.RowidsInRange`: the database of a success or a failure, and the persisted and the
visible database of a pending outcome. Proof sketch: {name}`runSqlFrom_holds_ready` for
{name}`rowidsInRange_statementKeeps`. -/
theorem runSqlFrom_rowidsInRange (position : Nat) (script : List (Resolved.Statement × List Value))
    {state : SqlState} (holds : state.Holds (Database.RowidsInRange))
    (supported : supportedSqlFrom position script state = true) :
    (runSqlFrom position script state).Holds (Database.RowidsInRange) :=
  runSqlFrom_holds_ready (rowidsInRange_statementKeeps) position script holds supported (RunConditionsWith.always _ _ _)

/-- The run theorem of "rowids in range" for {name}`runSql`. For every script and database: if the database
satisfies {name}`Database.RowidsInRange`, and the script passes the support check at every statement that
the run reaches ({name}`supportedSqlFrom`), the outcome of {name}`runSql` satisfies {name}`Outcome.Holds`
for {name}`Database.RowidsInRange`. Proof sketch: {name}`runSql_holds_ready` for
{name}`rowidsInRange_statementKeeps`. -/
theorem runSql_rowidsInRange (script : List (Resolved.Statement × List Value)) {database : Database}
    (holds : Database.RowidsInRange database) (supported : supportedSqlFrom 0 script { database } = true) :
    (runSql script database).Holds (Database.RowidsInRange) :=
  runSql_holds_ready (rowidsInRange_statementKeeps) script holds supported (RunConditionsWith.always _ _ _)


end Belay.Sqlite.Model
