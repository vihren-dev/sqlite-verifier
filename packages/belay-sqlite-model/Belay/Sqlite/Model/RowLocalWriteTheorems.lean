import Belay.Sqlite.Model.RowLocalUpsert
import Belay.Sqlite.Model.RowLocalWrites

set_option doc.verso true

/-! The theorems of the atoms "not null", "types fit" and "checks hold" (ADR 0022, D3, slice 3) for plain
INSERT, UPDATE, DELETE and upsert, and for the statements that write no row, one theorem for each atom.
Each is {lit}`RowLocalWrites` or {lit}`RowLocalUpsert` for the atom, and assumes only its own atom. -/

namespace Belay.Sqlite.Model

/-- For every clock value, counters, parameter list and plain INSERT (no foreign key rules and no trigger
programs) and database: if the database satisfies {name}`Database.NotNull`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_insert_rowLocal` with {name}`Table.notNullAtom`. -/
theorem runStatement_insert_notNull (clock : Int) (counters : Counters) (parameters : List Value) (target : Nat) (rows : List (List Resolved.Cell))
    (returning : List (Resolved.Expr × String)) (subqueries : List Resolved.Query) {database : Database}
    (notNull : database.NotNull) :
    (runStatement clock counters parameters (.insert target rows returning subqueries none) database).effect.Satisfies Database.NotNull :=
  runStatement_insert_rowLocal Table.notNullAtom clock counters parameters target rows returning subqueries notNull

/-- For every clock value, counters, parameter list and plain INSERT (no foreign key rules and no trigger
programs) and database: if the database satisfies {name}`Database.TypesFit`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_insert_rowLocal` with {name}`Table.typesFitAtom`. -/
theorem runStatement_insert_typesFit (clock : Int) (counters : Counters) (parameters : List Value) (target : Nat) (rows : List (List Resolved.Cell))
    (returning : List (Resolved.Expr × String)) (subqueries : List Resolved.Query) {database : Database}
    (fits : database.TypesFit) :
    (runStatement clock counters parameters (.insert target rows returning subqueries none) database).effect.Satisfies Database.TypesFit :=
  runStatement_insert_rowLocal Table.typesFitAtom clock counters parameters target rows returning subqueries fits

/-- For every clock value, counters, parameter list and plain INSERT (no foreign key rules and no trigger
programs) and database: if the database satisfies {name}`Database.ChecksHold`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_insert_rowLocal` with {name}`Table.checksHoldAtom`. -/
theorem runStatement_insert_checksHold (clock : Int) (counters : Counters) (parameters : List Value) (target : Nat) (rows : List (List Resolved.Cell))
    (returning : List (Resolved.Expr × String)) (subqueries : List Resolved.Query) {database : Database}
    (holds : database.ChecksHold) :
    (runStatement clock counters parameters (.insert target rows returning subqueries none) database).effect.Satisfies Database.ChecksHold :=
  runStatement_insert_rowLocal Table.checksHoldAtom clock counters parameters target rows returning subqueries holds

/-- For every clock value, counters, parameter list and plain UPDATE (no foreign key rules and no trigger
programs) and database: if the database satisfies {name}`Database.NotNull`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_update_rowLocal` with {name}`Table.notNullAtom`. -/
theorem runStatement_update_notNull (clock : Int) (counters : Counters) (parameters : List Value) (target : Nat) (assignments : List (Nat × Resolved.Expr))
    (filter : Option Resolved.Expr) (returning : List (Resolved.Expr × String)) (subqueries : List Resolved.Query)
    {database : Database}
    (notNull : database.NotNull) :
    (runStatement clock counters parameters (.update target assignments filter returning subqueries none) database).effect.Satisfies Database.NotNull :=
  runStatement_update_rowLocal Table.notNullAtom clock counters parameters target assignments filter returning subqueries notNull

/-- For every clock value, counters, parameter list and plain UPDATE (no foreign key rules and no trigger
programs) and database: if the database satisfies {name}`Database.TypesFit`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_update_rowLocal` with {name}`Table.typesFitAtom`. -/
theorem runStatement_update_typesFit (clock : Int) (counters : Counters) (parameters : List Value) (target : Nat) (assignments : List (Nat × Resolved.Expr))
    (filter : Option Resolved.Expr) (returning : List (Resolved.Expr × String)) (subqueries : List Resolved.Query)
    {database : Database}
    (fits : database.TypesFit) :
    (runStatement clock counters parameters (.update target assignments filter returning subqueries none) database).effect.Satisfies Database.TypesFit :=
  runStatement_update_rowLocal Table.typesFitAtom clock counters parameters target assignments filter returning subqueries fits

/-- For every clock value, counters, parameter list and plain UPDATE (no foreign key rules and no trigger
programs) and database: if the database satisfies {name}`Database.ChecksHold`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_update_rowLocal` with {name}`Table.checksHoldAtom`. -/
theorem runStatement_update_checksHold (clock : Int) (counters : Counters) (parameters : List Value) (target : Nat) (assignments : List (Nat × Resolved.Expr))
    (filter : Option Resolved.Expr) (returning : List (Resolved.Expr × String)) (subqueries : List Resolved.Query)
    {database : Database}
    (holds : database.ChecksHold) :
    (runStatement clock counters parameters (.update target assignments filter returning subqueries none) database).effect.Satisfies Database.ChecksHold :=
  runStatement_update_rowLocal Table.checksHoldAtom clock counters parameters target assignments filter returning subqueries holds

/-- For every clock value, counters, parameter list and plain DELETE (no foreign key rules and no trigger
programs) and database: if the database satisfies {name}`Database.NotNull`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_delete_rowLocal` with {name}`Table.notNullAtom`. -/
theorem runStatement_delete_notNull (clock : Int) (counters : Counters) (parameters : List Value) (target : Nat) (filter : Option Resolved.Expr)
    (returning : List (Resolved.Expr × String)) (subqueries : List Resolved.Query) {database : Database}
    (notNull : database.NotNull) :
    (runStatement clock counters parameters (.delete target filter returning subqueries none) database).effect.Satisfies Database.NotNull :=
  runStatement_delete_rowLocal Table.notNullAtom clock counters parameters target filter returning subqueries notNull

/-- For every clock value, counters, parameter list and plain DELETE (no foreign key rules and no trigger
programs) and database: if the database satisfies {name}`Database.TypesFit`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_delete_rowLocal` with {name}`Table.typesFitAtom`. -/
theorem runStatement_delete_typesFit (clock : Int) (counters : Counters) (parameters : List Value) (target : Nat) (filter : Option Resolved.Expr)
    (returning : List (Resolved.Expr × String)) (subqueries : List Resolved.Query) {database : Database}
    (fits : database.TypesFit) :
    (runStatement clock counters parameters (.delete target filter returning subqueries none) database).effect.Satisfies Database.TypesFit :=
  runStatement_delete_rowLocal Table.typesFitAtom clock counters parameters target filter returning subqueries fits

/-- For every clock value, counters, parameter list and plain DELETE (no foreign key rules and no trigger
programs) and database: if the database satisfies {name}`Database.ChecksHold`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_delete_rowLocal` with {name}`Table.checksHoldAtom`. -/
theorem runStatement_delete_checksHold (clock : Int) (counters : Counters) (parameters : List Value) (target : Nat) (filter : Option Resolved.Expr)
    (returning : List (Resolved.Expr × String)) (subqueries : List Resolved.Query) {database : Database}
    (holds : database.ChecksHold) :
    (runStatement clock counters parameters (.delete target filter returning subqueries none) database).effect.Satisfies Database.ChecksHold :=
  runStatement_delete_rowLocal Table.checksHoldAtom clock counters parameters target filter returning subqueries holds

/-- For every clock value, counters, parameter list, database and statement that writes no row (a query, a
setting, a prepare error, BEGIN, COMMIT or ROLLBACK) and database: if the database satisfies {name}`Database.NotNull`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_writesNone_rowLocal`. -/
theorem runStatement_writesNone_notNull (clock : Int) (counters : Counters) (parameters : List Value) {database : Database} (statement : Resolved.Statement)
    (writesNone : (∃ query subqueries, statement = .query query subqueries) ∨ (∃ setting on, statement = .setting setting on) ∨
      (∃ error, statement = .prepareError error) ∨ statement = .begin ∨ statement = .commit ∨ statement = .rollback)
    (notNull : database.NotNull) :
    (runStatement clock counters parameters statement database).effect.Satisfies Database.NotNull :=
  runStatement_writesNone_rowLocal (atom := Table.NotNull) clock counters parameters notNull statement writesNone

/-- For every clock value, counters, parameter list, database and statement that writes no row (a query, a
setting, a prepare error, BEGIN, COMMIT or ROLLBACK) and database: if the database satisfies {name}`Database.TypesFit`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_writesNone_rowLocal`. -/
theorem runStatement_writesNone_typesFit (clock : Int) (counters : Counters) (parameters : List Value) {database : Database} (statement : Resolved.Statement)
    (writesNone : (∃ query subqueries, statement = .query query subqueries) ∨ (∃ setting on, statement = .setting setting on) ∨
      (∃ error, statement = .prepareError error) ∨ statement = .begin ∨ statement = .commit ∨ statement = .rollback)
    (fits : database.TypesFit) :
    (runStatement clock counters parameters statement database).effect.Satisfies Database.TypesFit :=
  runStatement_writesNone_rowLocal (atom := Table.TypesFit) clock counters parameters fits statement writesNone

/-- For every clock value, counters, parameter list, database and statement that writes no row (a query, a
setting, a prepare error, BEGIN, COMMIT or ROLLBACK) and database: if the database satisfies {name}`Database.ChecksHold`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_writesNone_rowLocal`. -/
theorem runStatement_writesNone_checksHold (clock : Int) (counters : Counters) (parameters : List Value) {database : Database} (statement : Resolved.Statement)
    (writesNone : (∃ query subqueries, statement = .query query subqueries) ∨ (∃ setting on, statement = .setting setting on) ∨
      (∃ error, statement = .prepareError error) ∨ statement = .begin ∨ statement = .commit ∨ statement = .rollback)
    (holds : database.ChecksHold) :
    (runStatement clock counters parameters statement database).effect.Satisfies Database.ChecksHold :=
  runStatement_writesNone_rowLocal (atom := Table.ChecksHold) clock counters parameters holds statement writesNone

/-- For every clock value, counters, parameter list, INSERT with {lit}`ON CONFLICT` clauses or a conflict algorithm
without foreign key rules and trigger programs and database: if the database satisfies {name}`Database.NotNull`,
the database of the effect of {name}`runStatement` satisfies it, on success and on every error, which is
more than {name}`Effect.Satisfies` asks. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_upsert_rowLocal` with {name}`Table.notNullAtom`. -/
theorem runStatement_upsert_notNull (clock : Int) (counters : Counters) (parameters : List Value) (target : Nat) (rows : List (List Resolved.Cell))
    (clauses : List Resolved.ConflictClause) (returning : List (Resolved.Expr × String))
    (algorithm : Option ConflictAlgorithm) (subqueries : List Resolved.Query) {database : Database}
    (notNull : database.NotNull) :
    (effectDatabase (runStatement clock counters parameters (.upsert target rows clauses returning algorithm subqueries none) database).effect).NotNull :=
  runStatement_upsert_rowLocal Table.notNullAtom clock counters parameters target rows clauses returning algorithm subqueries notNull

/-- For every clock value, counters, parameter list, INSERT with {lit}`ON CONFLICT` clauses or a conflict algorithm
without foreign key rules and trigger programs and database: if the database satisfies {name}`Database.TypesFit`,
the database of the effect of {name}`runStatement` satisfies it, on success and on every error, which is
more than {name}`Effect.Satisfies` asks. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_upsert_rowLocal` with {name}`Table.typesFitAtom`. -/
theorem runStatement_upsert_typesFit (clock : Int) (counters : Counters) (parameters : List Value) (target : Nat) (rows : List (List Resolved.Cell))
    (clauses : List Resolved.ConflictClause) (returning : List (Resolved.Expr × String))
    (algorithm : Option ConflictAlgorithm) (subqueries : List Resolved.Query) {database : Database}
    (fits : database.TypesFit) :
    (effectDatabase (runStatement clock counters parameters (.upsert target rows clauses returning algorithm subqueries none) database).effect).TypesFit :=
  runStatement_upsert_rowLocal Table.typesFitAtom clock counters parameters target rows clauses returning algorithm subqueries fits

/-- For every clock value, counters, parameter list, INSERT with {lit}`ON CONFLICT` clauses or a conflict algorithm
without foreign key rules and trigger programs and database: if the database satisfies {name}`Database.ChecksHold`,
the database of the effect of {name}`runStatement` satisfies it, on success and on every error, which is
more than {name}`Effect.Satisfies` asks. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_upsert_rowLocal` with {name}`Table.checksHoldAtom`. -/
theorem runStatement_upsert_checksHold (clock : Int) (counters : Counters) (parameters : List Value) (target : Nat) (rows : List (List Resolved.Cell))
    (clauses : List Resolved.ConflictClause) (returning : List (Resolved.Expr × String))
    (algorithm : Option ConflictAlgorithm) (subqueries : List Resolved.Query) {database : Database}
    (holds : database.ChecksHold) :
    (effectDatabase (runStatement clock counters parameters (.upsert target rows clauses returning algorithm subqueries none) database).effect).ChecksHold :=
  runStatement_upsert_rowLocal Table.checksHoldAtom clock counters parameters target rows clauses returning algorithm subqueries holds

end Belay.Sqlite.Model
