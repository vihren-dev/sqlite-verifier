import Belay.Sqlite.SqlProofs

set_option doc.verso true

/-! Schema-only scripts and the clock (ADR 0012, amendment 5, slice 6e2): they do not read
it, so their support check holds at every clock assignment. -/

namespace Belay.Sqlite

/-- For every {name}`SchemaOnly` script, no statement reads the clock
({name}`scriptReadsClock`): CREATE TABLE and ADD COLUMN have no expressions. -/
theorem SchemaOnly.readsClock (guard : SchemaOnly script) : scriptReadsClock script = false := by
  simp only [scriptReadsClock, List.any_eq_false]
  intro statement member
  have first := guard statement member
  cases statement <;> simp_all [Resolved.Statement.readsClock]

/-- For every {name}`SchemaOnly` script with {name}`ModeledDefinitions` and every database,
the script is supported at every clock assignment ({name}`SupportedSql`). It follows from
{name}`supportedSqlFrom_schemaOnly` and {name}`SupportedSql.of_readsClock`. -/
theorem SupportedSql.schemaOnly (guard : SchemaOnly script) (modeled : ModeledDefinitions script) :
    SupportedSql script database :=
  SupportedSql.of_readsClock guard.readsClock (supportedSqlFrom_schemaOnly guard modeled)

end Belay.Sqlite
