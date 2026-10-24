import Lake
open Lake DSL System

/-! The surface: the library that users import, {lit}`Belay`, with SQLite under
{lit}`Belay.Sqlite` (ADR 0016, D1). It reads SQL text with the text package below it
({lit}`belaySqliteText`), which calls the SQLite parser library as native code while a file
elaborates, so the surface's modules are precompiled too. The text package's lakefile reads the
parser library's folder from the environment variable {lit}`BELAY_PARSER_LIBRARY`. -/

package belay

require belaySqliteModel from "../belay-sqlite-model"
require belaySqliteText from "../belay-sqlite-text"

/-- The surface library. Its modules are precompiled, so that the interpreter that runs a
file's commands calls the parser library's native code. The library names its modules: a root
{lit}`Belay` would make Lake take every module under {lit}`Belay`, the model's and the text
package's too, as part of this package. -/
@[default_target]
lean_lib Belay where
  roots := #[]
  globs := #[.one `Belay, .one `Belay.Sqlite, .one `Belay.Sqlite.ParseCommand, .one `Belay.Sqlite.Values, .one `Belay.Sqlite.Database,
    .one `Belay.Sqlite.Script, .one `Belay.Sqlite.SqlLiteral, .one `Belay.Sqlite.SqlParameters, .one `Belay.Sqlite.SqlTerm, .one `Belay.Sqlite.SqlDiagnostics, .one `Belay.Sqlite.EvalDatabase,
    .one `Belay.Sqlite.SqlBang, .one `Belay.Sqlite.Run, .one `Belay.Sqlite.Program, .one `Belay.Sqlite.Env, .one `Belay.Sqlite.ValueDisplay,
    .one `Belay.Sqlite.ProgramRun, .one `Belay.Sqlite.ProgramQueries, .one `Belay.Sqlite.ProgramLaws, .one `Belay.Sqlite.ProgramEnvLaws, .one `Belay.Sqlite.RunLaws, .one `Belay.Sqlite.DbDiagnostics,
    .one `Belay.Sqlite.DbBang, .one `Belay.Sqlite.Queries, .one `Belay.Sqlite.QueryLaws, .one `Belay.Sqlite.QueryBridge, .one `Belay.Sqlite.QueryCases, .one `Belay.Sqlite.SelectOneFrom, .one `Belay.Sqlite.SqlSimp, .one `Belay.Sqlite.SqlSimpLaws, .one `Belay.Sqlite.ExistsQuery, .one `Belay.Sqlite.NotExistsQuery, .one `Belay.Sqlite.SelectOneMayFail, .one `Belay.Sqlite.ExistsMayFail, .one `Belay.Sqlite.ScalarNoFrom, .one `Belay.Sqlite.SelectNoFrom, .one `Belay.Sqlite.CountQuery, .one `Belay.Sqlite.ColumnQuery, .one `Belay.Sqlite.TableInfoQuery, .one `Belay.Sqlite.DuplicateKeyQuery, .one `Belay.Sqlite.AggregateQuery, .one `Belay.Sqlite.UniqueLookupQuery, .one `Belay.Sqlite.SqlCommand]
  precompileModules := true
