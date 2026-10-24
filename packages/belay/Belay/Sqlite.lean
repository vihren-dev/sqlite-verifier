import Belay.Sqlite.ParseCommand
import Belay.Sqlite.Translation
import Belay.Sqlite.Values
import Belay.Sqlite.Database
import Belay.Sqlite.Script
import Belay.Sqlite.SqlParameters
import Belay.Sqlite.SqlTerm
import Belay.Sqlite.SqlDiagnostics
import Belay.Sqlite.EvalDatabase
import Belay.Sqlite.SqlBang
import Belay.Sqlite.Run
import Belay.Sqlite.Program
import Belay.Sqlite.Env
import Belay.Sqlite.ValueDisplay
import Belay.Sqlite.ProgramRun
import Belay.Sqlite.ProgramQueries
import Belay.Sqlite.ProgramLaws
import Belay.Sqlite.ProgramEnvLaws
import Belay.Sqlite.DbDiagnostics
import Belay.Sqlite.DbBang
import Belay.Sqlite.RunLaws
import Belay.Sqlite.Queries
import Belay.Sqlite.QueryLaws
import Belay.Sqlite.QueryBridge
import Belay.Sqlite.QueryCases
import Belay.Sqlite.SqlCommand
import Belay.Sqlite.SelectOneFrom
import Belay.Sqlite.SqlSimp
import Belay.Sqlite.SqlSimpLaws
import Belay.Sqlite.ExistsQuery
import Belay.Sqlite.NotExistsQuery
import Belay.Sqlite.SelectOneMayFail
import Belay.Sqlite.ExistsMayFail
import Belay.Sqlite.ScalarNoFrom
import Belay.Sqlite.SelectNoFrom
import Belay.Sqlite.CountQuery
import Belay.Sqlite.ColumnQuery
import Belay.Sqlite.TableInfoQuery
import Belay.Sqlite.DuplicateKeyQuery
import Belay.Sqlite.AggregateQuery
import Belay.Sqlite.UniqueLookupQuery

/-! The SQLite surface. It reads SQL text while a Lean file elaborates, with the SQLite parser
library in the Lean process, and translates the parse tree to the model's statement syntax with
the source range of each node ({lit}`Belay.Sqlite.Translation` of the text package below the
surface, ADR 0016, D2, amended). -/
