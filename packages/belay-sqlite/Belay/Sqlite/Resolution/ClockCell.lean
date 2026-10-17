import Belay.Sqlite.Resolution.QueryForm

set_option doc.verso true

/-! The cells of an INSERT row that read the statement's clock (ADR 0012, amendment 5,
slice 6e2). -/

namespace Belay.Sqlite.Resolved

/-- A cell of an INSERT row whose value reads the statement's clock (ADR 0012, amendment 5,
slice 6e2): the row and the column position, the value's expression, which reads no column,
and the column's affinity. A {lit}`VALUES` item with a time keyword and an omitted column
whose default is one are such cells. -/
structure ClockCell where
  /-- The position of the row among the statement's rows. -/
  row : Nat
  /-- The column position in table order. -/
  column : Nat
  /-- The expression of the value. -/
  value : Expr
  /-- The affinity with which the value is stored. -/
  affinity : Affinity
  deriving Repr, DecidableEq

end Belay.Sqlite.Resolved
