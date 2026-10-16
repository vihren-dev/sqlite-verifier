set_option doc.verso true

/-! The conflict algorithms of SQLite (ADR 0012, amendment 4, slice 5d): what a statement
does when a row fails a unique key or NOT NULL. The {lit}`OR` clause of INSERT and the
{lit}`ON CONFLICT` clause of a constraint name one of them. -/

namespace Belay.Sqlite

/-- A conflict algorithm. ABORT is the default of every constraint and statement. -/
inductive ConflictAlgorithm where
  /-- {lit}`ROLLBACK`: fail the statement and roll back the open transaction. -/
  | rollback
  /-- {lit}`ABORT`: fail the statement and undo its changes. -/
  | abort
  /-- {lit}`FAIL`: fail the statement and keep the changes of its earlier rows. -/
  | fail
  /-- {lit}`IGNORE`: skip the row. -/
  | ignore
  /-- {lit}`REPLACE`: delete the conflicting rows, or use the default for a NULL. -/
  | replace
  deriving Repr, DecidableEq

end Belay.Sqlite
