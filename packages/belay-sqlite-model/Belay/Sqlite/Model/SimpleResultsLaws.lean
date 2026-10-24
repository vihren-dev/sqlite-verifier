import Belay.Sqlite.Model.SimpleQueryLaws

set_option doc.verso true

/-! The result rows of a simple query (ADR 0017, S4): a query without {lit}`ORDER BY` sorts nothing, so
its result rows are the output of the source rows that {lit}`WHERE` keeps, in the order of the source rows. The
subquery forms {lit}`x IN (SELECT c FROM t WHERE p)` and a scalar subquery read these rows. -/

namespace Belay.Sqlite.Model.Resolved

/-- For every order that holds between any two items, inserting an item puts it at the end of the list. Proof
sketch: induction on the list; each leading item is at most the new item. -/
theorem insertStable_of_total {α : Type} (le : α → α → Bool) (always : ∀ a b, le a b = true) (item : α) :
    ∀ items : List α, insertStable le item items = items ++ [item]
  | [] => rfl
  | head :: tail => by simp [insertStable, always, insertStable_of_total le always item tail]

/-- For every order that holds between any two items, the stable sort keeps the list as it is. Proof sketch:
each step of the fold appends the next item ({name}`insertStable_of_total`). -/
theorem stableSort_of_total {α : Type} (le : α → α → Bool) (always : ∀ a b, le a b = true) (items : List α) :
    stableSort le items = items := by
  have step : ∀ (sorted items : List α), items.foldl (fun sorted item => insertStable le item sorted) sorted =
      sorted ++ items := by
    intro sorted items
    induction items generalizing sorted with
    | nil => simp
    | cons head tail ih => rw [List.foldl_cons, insertStable_of_total le always, ih, List.append_assoc,
        List.singleton_append]
  simpa [stableSort] using step [] items

/-- For every simple query, over any rows, the result rows are the output rows of the source rows that
{lit}`WHERE` keeps, in their order: a scalar column gives its value on the row, and an aggregate column gives the aggregate
over the list of that one source row (the simple query has no {lit}`GROUP BY`, but the formula does not exclude an
aggregate column). Proof sketch: a query without
{lit}`ORDER BY` has no sort term, so every two records are in order and the sort keeps their order
({name}`stableSort_of_total`); the window takes all records. -/
theorem Query.Simple.results_eq {query : Query} (simple : query.Simple) (context : EvalContext)
    (rows : List (List Value)) :
    query.results context rows = (filtered context query rows).map fun row => query.columns.map fun
      | .scalar expression => expression.eval context row
      | .aggregate aggregate => aggregate.eval context [row] := by
  unfold Query.results
  dsimp only
  rw [stableSort_of_total _ (by simp [simple.orderBy, compareSort])]
  simp [Query.uniqueRecords, simple.compound, simple.distinct, simple.limit, simple.offset, records, simple.aggregate,
    simple.orderBy, Function.comp_def]
  intro _ _ _ _
  rfl

end Belay.Sqlite.Model.Resolved
