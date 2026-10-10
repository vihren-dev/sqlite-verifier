set_option doc.verso true

/-! The execution profile that name resolution reads: the SQLite release, its
build, the effective connection limits and the double-quoted-string settings.
SQLite checks most limits while it prepares a statement, so resolution needs them;
the remaining recorded settings belong to the execution semantics. -/

namespace Belay.Sqlite

/-- The effective run-time limits of a connection, as {lit}`sqlite3_limit(db, id, -1)`
reports them. A compile-time option sets the highest value and the connection can
lower it, so a profile records the value that applies. Use the documented
defaults below when no measured value exists. -/
structure Limits where
  /-- {lit}`SQLITE_LIMIT_COLUMN`: columns in a table, an index or a result list. -/
  columns : Nat
  /-- {lit}`SQLITE_LIMIT_EXPR_DEPTH`: the depth of an expression tree. -/
  expressionDepth : Nat
  /-- {lit}`SQLITE_LIMIT_COMPOUND_SELECT`: terms in a compound SELECT. -/
  compoundSelect : Nat
  /-- {lit}`SQLITE_LIMIT_FUNCTION_ARG`: arguments of one function call. -/
  functionArguments : Nat
  /-- {lit}`SQLITE_LIMIT_VARIABLE_NUMBER`: the highest parameter number. -/
  variableNumber : Nat
  /-- {lit}`SQLITE_LIMIT_LENGTH`: the bytes of one text or blob value. -/
  length : Nat
  /-- {lit}`SQLITE_LIMIT_TRIGGER_DEPTH`: nested trigger depth. -/
  triggerDepth : Nat
  deriving Repr, DecidableEq

/-- The compile-time defaults that SQLite documents for the {lit}`SQLITE_MAX_*`
options ({lit}`limits.html`), which a connection keeps when nothing lowers them:
2,000 columns, expression depth 1,000, 500 compound terms, 1,000 function
arguments, parameter number 32,766, 1,000,000,000 bytes and trigger depth 1,000. -/
def Limits.documentedDefaults : Limits where
  columns := 2000
  expressionDepth := 1000
  compoundSelect := 500
  functionArguments := 1000
  variableNumber := 32766
  length := 1000000000
  triggerDepth := 1000

/-- The parts of an execution profile that name resolution reads. Supply the
release and source id of the measured build. When no measured profile exists,
build one from the documented defaults of the release, as below. -/
structure Profile where
  /-- The release, as {lit}`sqlite_version()` reports it, for example {lit}`3.51.0`. -/
  release : String
  /-- The build, as {lit}`sqlite_source_id()` reports it. -/
  sourceId : String
  /-- The effective limits of the connection. -/
  limits : Limits
  /-- {lit}`SQLITE_DBCONFIG_DQS_DML`: whether a double-quoted name that matches no
  column is a string literal in DML statements. -/
  dqsDml : Bool
  /-- {lit}`SQLITE_DBCONFIG_DQS_DDL`: the same setting for DDL statements. -/
  dqsDdl : Bool
  deriving Repr, DecidableEq

/-- A profile with the documented default limits and the default double-quoted
string settings (both on), for the given release and source id. Use it until a
measured profile exists, as {lit}`verify` does for a release version. -/
def Profile.documented (release sourceId : String) : Profile where
  release := release
  sourceId := sourceId
  limits := Limits.documentedDefaults
  dqsDml := true
  dqsDdl := true

end Belay.Sqlite
