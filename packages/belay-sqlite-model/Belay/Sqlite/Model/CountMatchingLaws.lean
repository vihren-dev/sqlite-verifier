import Belay.Sqlite.Model.CountSubqueryOutput

set_option doc.verso true

/-! The number of rows of a table for which a condition is true (ADR 0017, S4): it does not depend on the
scan order, so it is the number of stored rows that satisfy the condition, and with no condition it is the
number of stored rows. -/

namespace Belay.Sqlite.Model

/-- For every context, condition and table, the number of rows for which the condition is true
({name}`Resolved.countMatching`) is the number of stored rows for which it is true, in the order of the
table's storage. Proof sketch: the scan order is a permutation of the stored rows
({name}`Table.scanRows_perm`), and a filter keeps the number of items of a permutation. -/
theorem Resolved.countMatching_eq (context : Resolved.EvalContext) (condition : Option Resolved.Expr) (table : Table) :
    Resolved.countMatching context condition table =
      (table.rows.filter fun row => condition.all fun expression =>
        Resolved.truthy (expression.eval context row.values)).length := by
  unfold Resolved.countMatching Resolved.sourceRows
  rw [List.filter_map, List.length_map]
  exact (table.scanRows_perm.filter _).length_eq

/-- For every context and table, the number of rows for which no condition is given is the number of stored rows.
It is zero for a table without rows. Proof sketch: {name}`Resolved.countMatching_eq`; a filter that keeps every row
keeps the list. -/
theorem Resolved.countMatching_none (context : Resolved.EvalContext) (table : Table) :
    Resolved.countMatching context none table = table.rows.length := by
  simp [Resolved.countMatching_eq]

end Belay.Sqlite.Model
