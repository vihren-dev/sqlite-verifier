import Belay.Sqlite.Model.AdmittedUpsertOrigins
import Belay.Sqlite.Model.AdmittedUpsertStatement

set_option doc.verso true

/-! The upsert and the five table atoms of {lit}`Database.Admitted` (ADR 0022, D3, slice 4). An upsert is
an INSERT with {lit}`ON CONFLICT` clauses or conflict algorithms, without foreign key rules and trigger
programs. Each theorem says: if the atom holds in the database, the effect of {lit}`runStatement` keeps
it, on success and on an error with {lit}`ExecutionError.constraintFail`. "Rowids distinct" needs
nothing more. The other four atoms assume that the run is ready ({lit}`StatementRun.ready`): the data
check of the upsert ({lit}`LiteralData.upsertReady`) gives the width and the stored form of the supplied
rows and the range of the rowids that the rows reach. "Rows aliased" also needs a valid catalog, which
says that the column of a rowid alias is not generated. -/

namespace Belay.Sqlite.Model

/-- For every clock value, counters, parameter list, target, rows of cells, clauses, returning list,
algorithm and subqueries, and every database whose rowids are distinct: the effect of an upsert without
rules satisfies "rowids distinct" ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have distinct rowids in every table. Any other error
requires nothing. The statement does not need to be ready. Proof sketch: each row that stores a table
checks {name}`LiteralData.rowidsDistinct` ({name}`LiteralData.upsertRow_distinct`). -/
theorem runStatement_upsert_rowidsDistinct (clock : Int) (counters : Counters) (parameters : List Value)
    (target : Nat) (rows : List (List Resolved.Cell)) (clauses : List Resolved.ConflictClause)
    (returning : List (Resolved.Expr × String)) (algorithm : Option ConflictAlgorithm)
    (subqueries : List Resolved.Query) {database : Database} (distinct : database.RowidsDistinct) :
    (runStatement clock counters parameters (.upsert target rows clauses returning algorithm subqueries none)
      database).effect.Satisfies Database.RowidsDistinct :=
  runStatement_upsert_satisfies_of_steps (atom := Table.RowidsDistinct) clock counters parameters target rows
    clauses returning algorithm subqueries distinct (fun _ _ _ => True) (fun _ _ => trivial)
    fun _ _ _ _ _ _ _ _ good _ run => ⟨(LiteralData.upsertRow_distinct good run).2, trivial⟩

/-- For every clock value, counters, parameter list, target, rows of cells, clauses, returning list,
algorithm and subqueries, and every database whose rowids are in range: if the run of an upsert without
rules is ready, the effect satisfies "rowids in range" ({name}`Effect.Satisfies`). Any error other than
{name}`ExecutionError.constraintFail` requires nothing. Proof sketch: the data check of the upsert
bounds the rowids of the table after every reached row ({name}`upsertReady_parts`,
{name}`LiteralData.upsertBounded_step`), and the table before a failed row is the one after the row
before. -/
theorem runStatement_upsert_rowidsInRange (clock : Int) (counters : Counters) (parameters : List Value)
    (target : Nat) (rows : List (List Resolved.Cell)) (clauses : List Resolved.ConflictClause)
    (returning : List (Resolved.Expr × String)) (algorithm : Option ConflictAlgorithm)
    (subqueries : List Resolved.Query) {database : Database} (inRange : database.RowidsInRange)
    (ready : (runStatement clock counters parameters
      (.upsert target rows clauses returning algorithm subqueries none) database).ready = true) :
    (runStatement clock counters parameters (.upsert target rows clauses returning algorithm subqueries none)
      database).effect.Satisfies Database.RowidsInRange :=
  runStatement_upsert_satisfies_of_steps (atom := Table.RowidsInRange) clock counters parameters target rows
    clauses returning algorithm subqueries inRange
    (fun table queue current => LiteralData.upsertBounded (LiteralData.upsertSteps
      (Resolved.statementContext clock counters parameters database subqueries) (database.keys target table)
      (database.catalog.writePolicy target table.shape algorithm) clauses current queue) = true)
    (fun _ found => (upsertReady_parts (runStatement_upsert_ready ready found)).2.2.2)
    fun _ _ _ _ _ _ _ _ _ ahead run => LiteralData.upsertBounded_step run ahead

/-- For every clock value, counters, parameter list, target, rows of cells, clauses, returning list,
algorithm and subqueries, and every database whose rows are wide: if the run of an upsert without rules
is ready, the effect satisfies "rows wide" ({name}`Effect.Satisfies`): every row has one cell for each
column. Any error other than {name}`ExecutionError.constraintFail` requires nothing. Proof sketch: the
data check of the upsert gives the width of each supplied row ({name}`upsertReady_parts`); each row
of a table after a reached row has an origin that keeps the width ({name}`LiteralData.upsertOrigin_wide`,
{name}`LiteralData.upsertRow_rowsOk`). -/
theorem runStatement_upsert_rowsWide (clock : Int) (counters : Counters) (parameters : List Value)
    (target : Nat) (rows : List (List Resolved.Cell)) (clauses : List Resolved.ConflictClause)
    (returning : List (Resolved.Expr × String)) (algorithm : Option ConflictAlgorithm)
    (subqueries : List Resolved.Query) {database : Database} (wide : database.RowsWide)
    (ready : (runStatement clock counters parameters
      (.upsert target rows clauses returning algorithm subqueries none) database).ready = true) :
    (runStatement clock counters parameters (.upsert target rows clauses returning algorithm subqueries none)
      database).effect.Satisfies Database.RowsWide :=
  runStatement_upsert_satisfies_of_steps (atom := Table.RowsWide) clock counters parameters target rows
    clauses returning algorithm subqueries wide
    (fun table queue _ => ∀ values ∈ queue, values.length = table.shape.columns.length)
    (fun _ found => (upsertReady_parts (runStatement_upsert_ready ready found)).2.1)
    fun _ _ _ _ values _ _ same good ahead run =>
      ⟨(LiteralData.upsertRow_rowsOk (fun shape row => row.values.length = shape.columns.length) good
        (fun _ origin => LiteralData.upsertOrigin_wide good (same ▸ ahead values (List.mem_cons_self ..)) origin)
        run).2, fun other member => ahead other (List.mem_cons_of_mem _ member)⟩

/-- For every clock value, counters, parameter list, target, rows of cells, clauses, returning list,
algorithm and subqueries, and every database whose rows are stored: if the run of an upsert without
rules is ready, the effect satisfies "rows stored" ({name}`Effect.Satisfies`): every cell is in the
stored form of its column. Any error other than {name}`ExecutionError.constraintFail` requires nothing.
Proof sketch: the data check of the upsert gives {name}`LiteralData.aliasReady` and the stored form of
each supplied row ({name}`upsertReady_parts`); each row of a table after a reached row has an origin
that keeps it ({name}`LiteralData.upsertOrigin_stored`, {name}`LiteralData.upsertRow_rowsOk`). -/
theorem runStatement_upsert_rowsStored (clock : Int) (counters : Counters) (parameters : List Value)
    (target : Nat) (rows : List (List Resolved.Cell)) (clauses : List Resolved.ConflictClause)
    (returning : List (Resolved.Expr × String)) (algorithm : Option ConflictAlgorithm)
    (subqueries : List Resolved.Query) {database : Database} (stored : database.RowsStored)
    (ready : (runStatement clock counters parameters
      (.upsert target rows clauses returning algorithm subqueries none) database).ready = true) :
    (runStatement clock counters parameters (.upsert target rows clauses returning algorithm subqueries none)
      database).effect.Satisfies Database.RowsStored :=
  runStatement_upsert_satisfies_of_steps (atom := Table.RowsStored) clock counters parameters target rows
    clauses returning algorithm subqueries stored
    (fun table queue _ => ∀ values ∈ queue, ∀ (position : Nat) (column : CatalogColumn) (value : Value),
      table.shape.columns[position]? = some column → values[position]? = some value →
        Value.store column.affinity value = value)
    (fun _ found => (upsertReady_parts (runStatement_upsert_ready ready found)).2.2.1)
    fun _ found _ _ values _ _ same good ahead run =>
      ⟨(LiteralData.upsertRow_rowsOk (fun shape row => row.Stored shape.columns) good
        (fun _ origin => LiteralData.upsertOrigin_stored good
          (same ▸ (upsertReady_parts (runStatement_upsert_ready ready found)).1)
          (same ▸ ahead values (List.mem_cons_self ..)) origin) run).2,
        fun other member => ahead other (List.mem_cons_of_mem _ member)⟩

/-- For every limits, clock value, counters, parameter list, target, rows of cells, clauses, returning
list, algorithm and subqueries, and every database whose rows are aliased and whose catalog is valid under
the limits: if the run of an upsert without rules is ready, the effect satisfies "rows aliased"
({name}`Effect.Satisfies`): the alias cell of every row is the integer rowid. Any error other than
{name}`ExecutionError.constraintFail` requires nothing. Proof sketch: a valid catalog does not generate
the alias column ({name}`Database.aliasUngenerated`), the data check of the upsert gives the width of
each supplied row ({name}`upsertReady_parts`), and each row of a table after a reached row has an origin
that is aliased ({name}`LiteralData.upsertOrigin_aliased`, {name}`LiteralData.upsertRow_rowsOk`). -/
theorem runStatement_upsert_rowsAliased (limits : Limits) (clock : Int) (counters : Counters)
    (parameters : List Value) (target : Nat) (rows : List (List Resolved.Cell))
    (clauses : List Resolved.ConflictClause) (returning : List (Resolved.Expr × String))
    (algorithm : Option ConflictAlgorithm) (subqueries : List Resolved.Query) {database : Database}
    (aliased : database.RowsAliased) (valid : database.catalog.Valid limits)
    (ready : (runStatement clock counters parameters
      (.upsert target rows clauses returning algorithm subqueries none) database).ready = true) :
    (runStatement clock counters parameters (.upsert target rows clauses returning algorithm subqueries none)
      database).effect.Satisfies Database.RowsAliased :=
  runStatement_upsert_satisfies_of_steps (atom := Table.RowsAliased) clock counters parameters target rows
    clauses returning algorithm subqueries aliased
    (fun table queue _ => ∀ values ∈ queue, values.length = table.shape.columns.length)
    (fun _ found => (upsertReady_parts (runStatement_upsert_ready ready found)).2.1)
    fun _ found _ _ values _ _ same good ahead run =>
      ⟨(LiteralData.upsertRow_rowsOk (fun shape row => row.Aliased shape.rowidAlias) good
        (fun _ origin => LiteralData.upsertOrigin_aliased good (same ▸ Database.aliasUngenerated valid found)
          (same ▸ ahead values (List.mem_cons_self ..)) origin) run).2,
        fun other member => ahead other (List.mem_cons_of_mem _ member)⟩

end Belay.Sqlite.Model
