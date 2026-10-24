import Belay.Sqlite.Model.Resolution.ScopeNames
import Belay.Sqlite.Model.Resolution.QueryAffinity
import Belay.Sqlite.Model.Resolution.Values

set_option doc.verso true

/-! The operands of unqualified names over a scope with merged columns (ADR 0012,
amendment 3; slice 4d): a name that reads one column is that column with its affinity,
and a name that reads several, after full joins, is their coalesce, which has no
affinity, as in SQLite. -/

namespace Belay.Sqlite.Model

/-- The coalesce of the columns at the positions, in order: the first column that is not
NULL. One position is that column; no position, which {name}`Scope.resolveName` never
gives, is NULL. -/
def coalesceColumns : List Nat → Resolved.Expr
  | [] => .literal .null
  | [position] => .column position
  | position :: rest => .coalesce (.column position) (coalesceColumns rest)

/-- The operand of a name that reads the columns at the positions
({name}`NameResolution.found`): one column with its affinity, except a cell of a trigger's
{lit}`NEW` or {lit}`OLD` row ({name}`Scope.triggerCell`), which has no affinity, as in SQLite
(ADR 0018, D5); or the coalesce of several with no affinity. -/
def Scope.nameOperand (scope : Scope) : List Nat → Operand
  | [position] => (.column position,
      if scope.triggerCell position then none else scope.affinityAt position)
  | reads => (coalesceColumns reads, none)

/-- The operand of a name in an expression that reads the columns at the positions
({name}`Scope.nameOperand`), or the restriction {name}`RestrictionKind.tableFunction` when it
reads an argument column of a table-valued pragma ({name}`Scope.argumentCell`): SQLite passes a
condition on such a column to the pragma, which changes the rows. -/
def Scope.nameRead (scope : Scope) (reads : List Nat) : Except ValueIssue Operand :=
  if reads.any scope.argumentCell then .error (.restriction [] .tableFunction) else .ok (scope.nameOperand reads)

/-- The index of the source whose cells hold the position of the concatenated row; the
number of sources for a position after the last cell. -/
def Scope.sourceOf (scope : Scope) (position : Nat) : Nat :=
  (scope.findIdx? fun source => position < source.offset + source.columns.length).getD scope.length

/-- The operand of the column at the position in the expansion of {lit}`*` or
{lit}`x.*`, as SQLite expands it (checked on native 3.51.0): when the column's source is
to the left of a right or full join and a later join merges the column's name, the
expansion is the unqualified name ({name}`Scope.resolveName`), so the column shows the
right column or the coalesce of a merged pair; otherwise the qualified name of the column
({name}`Scope.resolveQualified`), which is the column itself unless two sources have the
name, and then SQLite's {lit}`ambiguous column name: main.x.c` for a column that no join
merged. -/
def Scope.starOperand (scope : Scope) (position : Nat) (column : CatalogColumn) : Except ValueIssue Operand :=
  let index := scope.sourceOf position
  let later := scope.drop (index + 1)
  let rightAfter := later.any fun source => source.mergeRule != .keepLeft
  let mergedLater := later.any fun source => (columnPosition source.columns column.name).any (source.merged.contains ·)
  if rightAfter && mergedLater then match scope.resolveName column.name with
    | .found _ reads => .ok (scope.nameOperand reads)
    | .missing | .ambiguous => .ok (scope.nameOperand [position])
  else
    let name := (scope[index]?.map (·.name)).getD default
    match scope.resolveQualified name column.name with
    | .found _ reads => .ok (scope.nameOperand reads)
    | .missing => .ok (scope.nameOperand [position])
    | .ambiguous => .error (.prepare (.ambiguousColumn ⟨bytes! "main." ++ name.bytes ++ [46] ++ column.name.bytes⟩))

end Belay.Sqlite.Model
