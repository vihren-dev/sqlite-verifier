import Belay.Sqlite.Model.Execution

set_option doc.verso true

/-! Kernel examples for the indexed derived-source evaluator: complete-row certainty, joins,
outer cells and the statement's parameter, clock and counter context. Text and name resolution
are checked separately; these examples exercise the resolved query primitive directly. -/

namespace Belay.Sqlite.Model.Resolved.DerivedSourceExamples

/-- A query of the supplied columns with no source and no window. -/
def select (columns : List Output) : Query :=
  { sources := [], filter := none, aggregate := false, groupBy := [], columns,
    names := columns.map fun _ => "value", orderBy := [], offset := 0, limit := none }

/-- A fixed source of two integer columns, with equal first values and different second values. -/
def pairs : QuerySource :=
  { kind := .inner, source := .pragma (.fixed 2 [[.integer 1, .integer 2], [.integer 1, .integer 3]]),
    condition := none }

/-- Select both columns of the fixed source, with the optional limit. -/
def pairQuery (limit : Option Nat := none) : Query :=
  { select [.scalar (.column 0), .scalar (.column 1)] with sources := [pairs], limit }

/-- A query that reads the complete two-column result of indexed subquery 0. -/
def fromPairs : Query :=
  { pairQuery with sources := [{ kind := .inner, source := .subquery 0 2, condition := none }] }

/-- Without a window, the indexed source gives both complete rows. -/
example : (fromPairs.runOn 0 {} [] {} [pairQuery]).map (·.2.rows) =
    some [[.integer 1, .integer 2], [.integer 1, .integer 3]] := by decide +kernel

/-- A one-row window has a certain first-column multiset but uncertain complete rows. -/
example : let run := (pairQuery (some 1)).subqueryRun (.plain 0) {} []
    run.rowsCertain = true ∧ run.sourceCertain = false := by decide +kernel

/-- The containing query refuses a source whose window can choose different second columns. -/
example : fromPairs.runOn 0 {} [] {} [pairQuery (some 1)] = none := by decide +kernel

/-- Ordering by the distinct second column makes the one-row source certain. -/
example : (fromPairs.runOn 0 {} [] {}
    [{ pairQuery (some 1) with orderBy := [{ key := .output 1 }] }]).map (·.2.rows) =
      some [[.integer 1, .integer 2]] := by decide +kernel

/-- A zero-row limit is certain even without an ordering term. -/
example : (fromPairs.runOn 0 {} [] {} [pairQuery (some 0)]).map (·.2.rows) = some [] := by decide +kernel

/-- Join one fixed value to a one-column indexed source under the supplied join kind. -/
def joined (kind : JoinKind) : Query :=
  { select [.scalar (.column 0), .scalar (.column 1)] with
    sources := [{ kind := .inner, source := .pragma (.fixed 1 [[.integer 9]]), condition := none },
      { kind, source := .subquery 0 1, condition := some (.literal (.integer 0)) }] }

/-- A constant result for the joined source. -/
def constant : Query := select [.scalar (.literal (.integer 4))]

/-- An unmatched inner join has no row. -/
example : ((joined .inner).runOn 0 {} [] {} [constant]).map (·.2.rows) = some [] := by decide +kernel

/-- An unmatched left join keeps its left row and extends it with NULL. -/
example : ((joined .left).runOn 0 {} [] {} [constant]).map (·.2.rows) =
    some [[.integer 9, .null]] := by decide +kernel

/-- An unmatched right join keeps its derived row and extends it with NULL. -/
example : ((joined .right).runOn 0 {} [] {} [constant]).map (·.2.rows) =
    some [[.null, .integer 4]] := by decide +kernel

/-- An unmatched full join keeps both sides with the respective NULL extension. -/
example : ((joined .full).runOn 0 {} [] {} [constant]).map (·.2.rows) =
    some [[.integer 9, .null], [.null, .integer 4]] := by decide +kernel

/-- The enclosing row survives an empty left source before a correlated right join. -/
def correlated : Query :=
  { select [.scalar (.column 0), .scalar (.column 1), .scalar (.column 2)] with
    outer := 1,
    sources := [{ kind := .inner, source := .pragma (.fixed 1 []), condition := none },
      { kind := .right, source := .subquery 0 1, condition := none }] }

/-- The source reads the enclosing value 7; the unmatched row retains it before its NULL padding. -/
example : let context := statementContext 0 {} [] {} [{ select [.scalar (.column 0)] with outer := 1 }]
    (correlated.subqueryRun context {} [.integer 7]).rows = [[.integer 7, .null, .integer 7]] := by
  decide +kernel

/-- A source reads the same parameter and connection counter as its containing statement. -/
example : (fromPairs.runOn 0 { changes := some 8 } [.integer 5] {}
    [select [.scalar (.parameter 1), .scalar (.counter .changes)]]).map (·.2.rows) =
      some [[.integer 5, .integer 8]] := by decide +kernel

/-- A source receives the supplied statement clock instead of resetting it. -/
example : let context := statementContext 212640249600000 {} [] {} [select [.scalar (.now .date)]]
    (({ kind := .inner, source := .subquery 0 1, condition := none } : QuerySource).join context {}
      { rows := [[]], width := 0, fault := .none }).map (·.rows) =
        some [[TimeKeyword.date.value 212640249600000]] := by decide +kernel

/-- A source failure is a refused source, rather than a successful empty relation. -/
example : let context : EvalContext :=
      { clock := 0, subqueries := fun _ _ => { rows := [], fault := .may } }
    ({ kind := .inner, source := .subquery 0 1, condition := none } : QuerySource).join context {}
      { rows := [[]], width := 0, fault := .none } = none := by decide +kernel

/-- A non-success ending refuses a source even when its expression fault is clear. -/
example : let context : EvalContext :=
      { clock := 0, subqueries := fun _ _ => { rows := [], fault := .none, ending := .mismatch } }
    ({ kind := .inner, source := .subquery 0 1, condition := none } : QuerySource).join context {}
      { rows := [[]], width := 0, fault := .none } = none := by decide +kernel

end Belay.Sqlite.Model.Resolved.DerivedSourceExamples
