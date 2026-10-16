import Belay.Sqlite.Resolution.QueryForm
import Belay.Sqlite.Resolution.ConflictAlgorithm

set_option doc.verso true

/-! The resolved form of the {lit}`ON CONFLICT` clauses of INSERT (ADR 0012, amendment
4, slice 5c): each target is the column positions of one key of the table, and the
expressions of {lit}`DO UPDATE` read the existing row followed by the proposed row
({lit}`excluded`), so a column position below the table's width reads the existing row
and the same position plus the width reads the proposed row. -/

namespace Belay.Sqlite.Resolved

/-- What a resolved {lit}`ON CONFLICT` clause does with a row that conflicts. -/
inductive ConflictAction where
  /-- {lit}`DO NOTHING`: skip the row. -/
  | nothing
  /-- {lit}`DO UPDATE`: set each table position to its expression, when the optional
  filter is true, on the existing row followed by the proposed row. -/
  | update (assignments : List (Nat × Expr)) (filter : Option Expr)
  deriving Repr, DecidableEq

/-- One resolved {lit}`ON CONFLICT` clause: the column positions of the key that its
target names, in key order, or {lean}`(none : Option (List Nat))` for a clause without
target, which handles a conflict on any key; and its action. -/
structure ConflictClause where
  /-- The key of the target, or none. -/
  target : Option (List Nat)
  /-- The action. -/
  action : ConflictAction
  deriving Repr, DecidableEq

/-- The algorithm that applies to each constraint of an INSERT: the statement's
{lit}`OR` algorithm, else the constraint's own, else ABORT. {lit}`keys` has one entry for
each key of the statement, in its order, and {lit}`notNull` one for each column. A
position without an entry is ABORT. -/
structure ConflictPolicy where
  /-- The algorithm of each key. -/
  keys : List ConflictAlgorithm
  /-- The algorithm of the NOT NULL constraint of each column. -/
  notNull : List ConflictAlgorithm
  deriving Repr, DecidableEq

end Belay.Sqlite.Resolved
