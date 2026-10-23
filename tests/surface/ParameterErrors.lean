import Belay

/-! A fixture of `tests/surface_parameters_test.py`: each wrong parameter of `sql r"..."`
(`Belay/Sqlite/SqlParameters.lean`, `Belay/Sqlite/SqlTerm.lean`) and each parameter of `db!`
(`Belay/Sqlite/DbBang.lean`) is an error at the parameter in the SQL text. The test reads the
line and column (from 0) of each error. -/

open Belay.Sqlite

/-- A type without a coercion to `Value`. -/
structure NoValue where

/-- `$nosuch` names no Lean variable. -/
def unknownVariable : Script := sql r"SELECT $nosuch"
/-- `$n` is a variable of a type without a coercion to `Value`. -/
def noCoercion (n : NoValue) : Script := sql r"SELECT $n"
/-- `$a::b` is not a Lean identifier. -/
def notIdentifier : Script := sql r"SELECT $a::b"
/-- `$a(x)` is not a Lean identifier. -/
def notIdentifierCall : Script := sql r"SELECT $a(x)"
/-- `:id` and `@id` both give the Lean name `id`. -/
def colonAndAt := sql r"SELECT :id, @id"
/-- `:id` and `$id` both give the Lean name `id`. -/
def colonAndDollar (id : Value) := sql r"SELECT :id; SELECT $id"
/-- `$x` and `?1` get one number and give two Lean names. -/
def variableAndNumber (x : Value) := sql r"SELECT $x, ?1"
/-- `:a` and `?1` get one number and give two Lean names. -/
def nameAndNumber := sql r"SELECT :a, ?1"
/-- `db!` has no arguments, so its parameters have no value. -/
def inDatabase : Database := db! r"CREATE TABLE t(a); INSERT INTO t VALUES (:a), (?)"
