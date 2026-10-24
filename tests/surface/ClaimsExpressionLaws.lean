import Belay

/-! A fixture of `tests/surface_claims_test.py`: the expression laws of the simp set `sql_simp`
(ADR 0017, S4; `Belay/Sqlite/SqlSimpLaws.lean`, the model's `ExprResolutionLaws.lean`,
`ExprEvalLaws.lean` and `ExprCalmLaws.lean`). The file fails to elaborate when the set does not turn
a written condition into the resolved expression, its calm or its truth. -/

open Belay.Sqlite
open Belay.Sqlite.Model hiding Database

/-- A condition with `BETWEEN`, `AND`, `NOT`, `OR`, `IS NULL`, a comparison with a parameter, and
the name of two columns of a table resolves to the resolved expression that the comment spells
out: each comparison has the affinity and the collation of the column that it names, and
`BETWEEN` is two comparisons. -/
example (columns : List CatalogColumn) (source : Identifier) (rowid : Bool) (amount status : Nat)
    (hasAmount : columnPosition columns (name! "amount") = some amount)
    (hasStatus : columnPosition columns (name! "status") = some status) :
    resolveOperand false (Scope.single source columns rowid) {} false
      (.and (.between (.identifier (name! "amount") .none) (.numeric "1") (.numeric "5") false)
        (.not (.or (.isNull (.identifier (name! "status") .none) false)
          (.compare .eq (.identifier (name! "status") .none) (.parameter 1))))) =
      .ok (.and (.and
            (.compare .ge (comparisonAffinity (columns[amount]?.map CatalogColumn.affinity) none) (.column amount)
              (.literal (.integer 1)) ((columns[amount]?.map (·.collation)).getD .binary))
            (.compare .le (comparisonAffinity (columns[amount]?.map CatalogColumn.affinity) none) (.column amount)
              (.literal (.integer 5)) ((columns[amount]?.map (·.collation)).getD .binary)))
          (.not (.or (.isNull (.column status) false)
            (.compare .eq (comparisonAffinity (columns[status]?.map CatalogColumn.affinity) none) (.column status)
              (.parameter 1) ((columns[status]?.map (·.collation)).getD .binary)))), none) := by
  simp [sql_simp, hasAmount, hasStatus]

/-- That condition is calm: it calls no function that can fail and reads neither the clock nor a
counter. -/
example (amount status : Nat) (affinity : Option Affinity) (collation : Collation) :
    (Resolved.Expr.and (.and (.compare .ge affinity (.column amount) (.literal (.integer 1)) collation)
      (.compare .le affinity (.column amount) (.literal (.integer 5)) collation))
        (.not (.or (.isNull (.column status) false)
          (.compare .eq affinity (.column status) (.parameter 1) collation)))).Calm := by
  simp [sql_simp]

/-- A `WHERE` keeps a row for `a AND b` exactly when it keeps it for `a` and for `b`, for `a OR b`
when it keeps it for one of them, and for `a IS NULL` exactly when `a` is NULL. -/
example (context : Resolved.EvalContext) (row : List Value) (a b : Resolved.Expr) :
    Resolved.truthy ((Resolved.Expr.and a b).eval context row) =
        (Resolved.truthy (a.eval context row) && Resolved.truthy (b.eval context row)) ∧
      Resolved.truthy ((Resolved.Expr.or a b).eval context row) =
        (Resolved.truthy (a.eval context row) || Resolved.truthy (b.eval context row)) ∧
      Resolved.truthy ((Resolved.Expr.isNull a false).eval context row) = (a.eval context row).isNull := by
  simp [sql_simp]
