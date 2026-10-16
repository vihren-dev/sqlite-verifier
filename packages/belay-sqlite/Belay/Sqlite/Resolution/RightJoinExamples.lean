import Belay.Sqlite.Resolution.UsingExamples

set_option doc.verso true

/-! Examples of {lit}`RIGHT` and {lit}`FULL` joins (ADR 0012, amendment 3; slice 4c),
checked by {lit}`#guard`: the resolved kinds and the rows of the joins. -/

namespace Belay.Sqlite.Resolution.RightJoinExamples
open Belay.Sqlite Syntax Resolution.Examples Resolution.JoinExamples Resolution.UsingExamples

/-- A table of two rows, with {lit}`a` 1 and 3. -/
def rightTwo : Table :=
  { shape := { columns := [{ name := "a", declaredType := some "INTEGER" }] },
    rows := [{ rowid := 1, values := [.integer 1] }, { rowid := 2, values := [.integer 3] }] }

/-- A table without rows. -/
def empty : Table := { shape := { columns := [{ name := "a", declaredType := some "INTEGER" }] }, rows := [] }

/-- A join of the kind to table 1 with the condition. -/
def join (kind : Resolved.JoinKind) (condition : Option Resolved.Expr := equal) : Resolved.Join :=
  { kind, table := 1, condition }

/-- The rows of a join of {name}`JoinExamples.left` (one column) and the table. -/
def rowsWith (kind : Resolved.JoinKind) (table : Table) (condition : Option Resolved.Expr := equal) :
    List (List Value) :=
  Resolved.joinRows 1 (Resolved.sourceRows JoinExamples.left) (join kind condition) table

-- The operators resolve to their kinds.
#guard (queryOver [.star] (table "t") [joined ["RIGHT"] (table "u") (some onA)]).map (·.joins.map (·.kind)) ==
  some [.right]
#guard (queryOver [.star] (table "t") [joined ["full", "Outer"] (table "u") (some onA)]).map (·.joins.map (·.kind)) ==
  some [.full]
-- A right join adds each unmatched right row padded on the left; a full join adds both sides.
#guard rowsWith .right rightTwo == [[.integer 1, .integer 1], [.null, .integer 3]]
#guard rowsWith .full rightTwo == [[.integer 1, .integer 1], [.integer 2, .null], [.null, .integer 3]]
-- An ON condition false for every row, and empty inputs.
#guard rowsWith .right rightTwo (some (.literal (.integer 0))) == [[.null, .integer 1], [.null, .integer 3]]
#guard rowsWith .full empty == [[.integer 1, .null], [.integer 2, .null]]
#guard rowsWith .right empty == []
#guard Resolved.joinRows 1 [] (join .full) rightTwo == [[.null, .integer 1], [.null, .integer 3]]

/-- A right join to table 2 on the second and third cells of the joined row. -/
def rightOnSecond : Resolved.Join := { kind := .right, table := 2, condition := some (.compare .eq (.column 1) (.column 2)) }

/-- A query of every cell of {name}`JoinExamples.left` full joined with table 1. -/
def fullQuery : Resolved.Query :=
  { table := some 0, joins := [join .full], filter := none, aggregate := false, groupBy := [], columns := [],
    names := [], orderBy := [], offset := 0, limit := none }

-- After an inner join, a right join pads every column of the left input.
#guard Resolved.joinRows 2 (rowsWith .inner rightTwo) rightOnSecond rightTwo ==
  [[.integer 1, .integer 1, .integer 1], [.null, .null, .integer 3]]
-- The source of a query folds the joins with the width of the tables so far.
#guard (fullQuery.source fun | 0 => some JoinExamples.left | 1 => some rightTwo | _ => none) ==
  some [[.integer 1, .integer 1], [.integer 2, .null], [.null, .integer 3]]

end Belay.Sqlite.Resolution.RightJoinExamples
