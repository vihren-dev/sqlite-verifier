import Belay.Sqlite.Model.RowLocalSchema

set_option doc.verso true

/-! The theorems of the atoms "not null", "types fit" and "checks hold" (ADR 0022, D3, slice 3) for CREATE
TABLE, CREATE INDEX, CREATE TRIGGER and DROP, one theorem for each atom. Each is
{lit}`RowLocalSchema` for the atom, and assumes only its own atom. None has a condition. -/

namespace Belay.Sqlite.Model

/-- For every clock value, parameter list and CREATE TABLE and database: if the database satisfies {name}`Database.NotNull`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_createTable_rowLocal` with {name}`Table.notNullAtom`. -/
theorem runStatement_createTable_notNull (clock : Int) (parameters : List Value) (target : Nat) (name : Identifier) (shape : CatalogTable)
    {database : Database}
    (notNull : database.NotNull) :
    (runStatement clock parameters (.createTable target name shape) database).effect.Satisfies Database.NotNull :=
  runStatement_createTable_rowLocal Table.notNullAtom clock parameters target name shape notNull

/-- For every clock value, parameter list and CREATE TABLE and database: if the database satisfies {name}`Database.TypesFit`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_createTable_rowLocal` with {name}`Table.typesFitAtom`. -/
theorem runStatement_createTable_typesFit (clock : Int) (parameters : List Value) (target : Nat) (name : Identifier) (shape : CatalogTable)
    {database : Database}
    (fits : database.TypesFit) :
    (runStatement clock parameters (.createTable target name shape) database).effect.Satisfies Database.TypesFit :=
  runStatement_createTable_rowLocal Table.typesFitAtom clock parameters target name shape fits

/-- For every clock value, parameter list and CREATE TABLE and database: if the database satisfies {name}`Database.ChecksHold`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_createTable_rowLocal` with {name}`Table.checksHoldAtom`. -/
theorem runStatement_createTable_checksHold (clock : Int) (parameters : List Value) (target : Nat) (name : Identifier) (shape : CatalogTable)
    {database : Database}
    (holds : database.ChecksHold) :
    (runStatement clock parameters (.createTable target name shape) database).effect.Satisfies Database.ChecksHold :=
  runStatement_createTable_rowLocal Table.checksHoldAtom clock parameters target name shape holds

/-- For every clock value, parameter list and CREATE INDEX and database: if the database satisfies {name}`Database.NotNull`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_createIndex_rowLocal` with {name}`Table.notNullAtom`. -/
theorem runStatement_createIndex_notNull (clock : Int) (parameters : List Value) (target : Nat) (name : Identifier) (index : CatalogIndex)
    {database : Database}
    (notNull : database.NotNull) :
    (runStatement clock parameters (.createIndex target name index) database).effect.Satisfies Database.NotNull :=
  runStatement_createIndex_rowLocal Table.notNullAtom clock parameters target name index notNull

/-- For every clock value, parameter list and CREATE INDEX and database: if the database satisfies {name}`Database.TypesFit`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_createIndex_rowLocal` with {name}`Table.typesFitAtom`. -/
theorem runStatement_createIndex_typesFit (clock : Int) (parameters : List Value) (target : Nat) (name : Identifier) (index : CatalogIndex)
    {database : Database}
    (fits : database.TypesFit) :
    (runStatement clock parameters (.createIndex target name index) database).effect.Satisfies Database.TypesFit :=
  runStatement_createIndex_rowLocal Table.typesFitAtom clock parameters target name index fits

/-- For every clock value, parameter list and CREATE INDEX and database: if the database satisfies {name}`Database.ChecksHold`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_createIndex_rowLocal` with {name}`Table.checksHoldAtom`. -/
theorem runStatement_createIndex_checksHold (clock : Int) (parameters : List Value) (target : Nat) (name : Identifier) (index : CatalogIndex)
    {database : Database}
    (holds : database.ChecksHold) :
    (runStatement clock parameters (.createIndex target name index) database).effect.Satisfies Database.ChecksHold :=
  runStatement_createIndex_rowLocal Table.checksHoldAtom clock parameters target name index holds

/-- For every clock value, parameter list and CREATE TRIGGER and database: if the database satisfies {name}`Database.NotNull`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_createTrigger_rowLocal` with {name}`Table.notNullAtom`. -/
theorem runStatement_createTrigger_notNull (clock : Int) (parameters : List Value) (target : Nat) (name : Identifier) (trigger : CatalogTrigger)
    {database : Database}
    (notNull : database.NotNull) :
    (runStatement clock parameters (.createTrigger target name trigger) database).effect.Satisfies Database.NotNull :=
  runStatement_createTrigger_rowLocal Table.notNullAtom clock parameters target name trigger notNull

/-- For every clock value, parameter list and CREATE TRIGGER and database: if the database satisfies {name}`Database.TypesFit`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_createTrigger_rowLocal` with {name}`Table.typesFitAtom`. -/
theorem runStatement_createTrigger_typesFit (clock : Int) (parameters : List Value) (target : Nat) (name : Identifier) (trigger : CatalogTrigger)
    {database : Database}
    (fits : database.TypesFit) :
    (runStatement clock parameters (.createTrigger target name trigger) database).effect.Satisfies Database.TypesFit :=
  runStatement_createTrigger_rowLocal Table.typesFitAtom clock parameters target name trigger fits

/-- For every clock value, parameter list and CREATE TRIGGER and database: if the database satisfies {name}`Database.ChecksHold`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_createTrigger_rowLocal` with {name}`Table.checksHoldAtom`. -/
theorem runStatement_createTrigger_checksHold (clock : Int) (parameters : List Value) (target : Nat) (name : Identifier) (trigger : CatalogTrigger)
    {database : Database}
    (holds : database.ChecksHold) :
    (runStatement clock parameters (.createTrigger target name trigger) database).effect.Satisfies Database.ChecksHold :=
  runStatement_createTrigger_rowLocal Table.checksHoldAtom clock parameters target name trigger holds

/-- For every clock value, parameter list and DROP without foreign key rules and trigger programs and database: if the database satisfies {name}`Database.NotNull`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_drop_rowLocal`; DROP has no condition. -/
theorem runStatement_drop_notNull (clock : Int) (parameters : List Value) (positions : List Nat) {database : Database}
    (notNull : database.NotNull) :
    (runStatement clock parameters (.drop positions none) database).effect.Satisfies Database.NotNull :=
  runStatement_drop_rowLocal (atom := Table.NotNull) clock parameters positions notNull

/-- For every clock value, parameter list and DROP without foreign key rules and trigger programs and database: if the database satisfies {name}`Database.TypesFit`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_drop_rowLocal`; DROP has no condition. -/
theorem runStatement_drop_typesFit (clock : Int) (parameters : List Value) (positions : List Nat) {database : Database}
    (fits : database.TypesFit) :
    (runStatement clock parameters (.drop positions none) database).effect.Satisfies Database.TypesFit :=
  runStatement_drop_rowLocal (atom := Table.TypesFit) clock parameters positions fits

/-- For every clock value, parameter list and DROP without foreign key rules and trigger programs and database: if the database satisfies {name}`Database.ChecksHold`,
the effect of {name}`runStatement` satisfies it ({name}`Effect.Satisfies`): the database of a success and that of an
error with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes nothing about the other atoms or the support check. Proof sketch: {name}`runStatement_drop_rowLocal`; DROP has no condition. -/
theorem runStatement_drop_checksHold (clock : Int) (parameters : List Value) (positions : List Nat) {database : Database}
    (holds : database.ChecksHold) :
    (runStatement clock parameters (.drop positions none) database).effect.Satisfies Database.ChecksHold :=
  runStatement_drop_rowLocal (atom := Table.ChecksHold) clock parameters positions holds

end Belay.Sqlite.Model
