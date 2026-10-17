import Belay.Sqlite.StatementClock

set_option doc.verso true

/-! Laws of a statement at a clock value ({lit}`StatementClock.lean`): a statement that does
not read the clock is unchanged at every clock value. -/

namespace Belay.Sqlite.Resolved

/-- For every list, predicate and member: if the predicate is false for every member of the
list ({lit}`List.any`), it is false for this member. Proof sketch: {lit}`List.any` is false
exactly when the predicate is false for every member. -/
theorem quietOf {p : α → Bool} {list : List α} {item : α} (free : list.any p = false) (member : item ∈ list) :
    p item = false := by
  simpa using List.any_eq_false.mp free item member

/-- For every list and function that keeps each member of the list, mapping the function
over the list keeps the list. Proof sketch: induction on the list; the head is kept by the
premise and the tail by the induction hypothesis. -/
theorem map_of_fixed {f : α → α} {list : List α} (fixed : ∀ item ∈ list, f item = item) : list.map f = list := by
  induction list with
  | nil => rfl
  | cons head tail ih =>
    simp only [List.map_cons, fixed head (by simp), ih fun item member => fixed item (by simp [member])]

/-- For every clock value and optional expression that does not read the clock, the
expression at the clock value is unchanged. Proof sketch: case split on the option; a
present expression is kept by {name}`Expr.atClock_of_readsClock`. -/
theorem option_atClock (clock : Int) : ∀ (term : Option Expr), term.any Expr.readsClock = false →
    term.map (·.atClock clock) = term
  | none, _ => rfl
  | some term, free => by simp_all [Expr.atClock_of_readsClock]

/-- For every clock value and list of {lit}`RETURNING` columns that do not read the clock,
the columns at the clock value are unchanged. Proof sketch: {name}`map_of_fixed`, with each
column's expression kept by {name}`Expr.atClock_of_readsClock`. -/
theorem returningAtClock_of_readsClock (clock : Int) (returning : List (Expr × String))
    (free : returningReadsClock returning = false) : returningAtClock clock returning = returning :=
  map_of_fixed fun (term, name) member => by
    have quiet : term.readsClock = false := by
      simpa using quietOf (p := fun (column : Expr × String) => column.1.readsClock) free member
    simp [Expr.atClock_of_readsClock _ _ quiet]

/-- For every clock value and list of assignments that do not read the clock, the
assignments at the clock value are unchanged. Proof sketch: {name}`map_of_fixed`, with each
assigned expression kept by {name}`Expr.atClock_of_readsClock`. -/
theorem assignments_atClock (clock : Int) (assignments : List (Nat × Expr))
    (free : assignments.any (·.2.readsClock) = false) :
    assignments.map (fun (position, value) => (position, value.atClock clock)) = assignments :=
  map_of_fixed fun (position, value) member => by
    have quiet : value.readsClock = false := by
      simpa using quietOf (p := fun (assignment : Nat × Expr) => assignment.2.readsClock) free member
    simp [Expr.atClock_of_readsClock _ _ quiet]

/-- For every clock value and list of expressions that do not read the clock, the
expressions at the clock value are unchanged. Proof sketch: {name}`map_of_fixed` with
{name}`Expr.atClock_of_readsClock` for each member. -/
theorem expressions_atClock (clock : Int) (terms : List Expr) (free : terms.any Expr.readsClock = false) :
    terms.map (·.atClock clock) = terms :=
  map_of_fixed fun term member => Expr.atClock_of_readsClock _ _ (by simpa using quietOf free member)

/-- For every clock value and query that does not read the clock, the query at the clock
value is the query. Proof sketch: each part that {name}`Query.atClock` maps is a part that
{name}`Query.readsClock` checks; {name}`map_of_fixed` keeps each list. -/
theorem Query.atClock_of_readsClock (clock : Int) (query : Query) (free : query.readsClock = false) :
    query.atClock clock = query := by
  simp only [Query.readsClock, Bool.or_eq_false_iff] at free
  obtain ⟨⟨⟨⟨⟨joins, functions⟩, filter⟩, groupBy⟩, columns⟩, orderBy⟩ := free
  have keptJoins : query.joins.map (fun join => { join with condition := join.condition.map (·.atClock clock) }) =
      query.joins := map_of_fixed fun join member => by
    simp [option_atClock _ _ (quietOf (p := fun (join : Join) => join.condition.any Expr.readsClock) joins member)]
  have keptFunctions : query.functions.map (fun each =>
      ({ json := each.json.atClock clock, path := each.path.map (·.atClock clock),
         condition := each.condition.map (·.atClock clock) } : EachSource)) = query.functions :=
    map_of_fixed fun each member => by
      have quiet := quietOf functions member
      simp only [Bool.or_eq_false_iff] at quiet
      simp [Expr.atClock_of_readsClock _ _ quiet.1.1, option_atClock _ _ quiet.1.2, option_atClock _ _ quiet.2]
  have keptColumns : query.columns.map (·.atClock clock) = query.columns := map_of_fixed fun output member => by
    have quiet := quietOf columns member
    cases output with
    | scalar term => simp_all [Output.atClock, Output.readsClock, Expr.atClock_of_readsClock]
    | aggregate function =>
      cases function <;> simp_all [Output.atClock, Output.readsClock, Aggregate.atClock, Expr.atClock_of_readsClock]
  have keptOrder : query.orderBy.map (fun (key, descending) => (key.atClock clock, descending)) = query.orderBy :=
    map_of_fixed fun (key, descending) member => by
      have quiet := quietOf orderBy member
      cases key <;> simp_all [SortKey.atClock, SortKey.readsClock, Expr.atClock_of_readsClock]
  simp only [Query.atClock, keptJoins, keptFunctions, keptColumns, keptOrder, option_atClock _ _ filter,
    expressions_atClock _ _ groupBy]

/-- For every clock value and {lit}`ON CONFLICT` clauses that do not read the clock, the
clauses at the clock value are unchanged. Proof sketch: {name}`map_of_fixed`; in each
clause, {name}`assignments_atClock` and {name}`option_atClock` keep the action. -/
theorem clauses_atClock (clock : Int) (clauses : List ConflictClause)
    (free : clauses.any ConflictClause.readsClock = false) : clauses.map (·.atClock clock) = clauses :=
  map_of_fixed fun clause member => by
    have quiet := quietOf free member
    obtain ⟨target, action⟩ := clause
    cases action with
    | nothing => rfl
    | update assignments filter =>
      simp only [ConflictClause.readsClock, Bool.or_eq_false_iff] at quiet
      simp [ConflictClause.atClock, assignments_atClock _ _ quiet.1, option_atClock _ _ quiet.2]

/-- For every clock value and statement that does not read the clock
({name}`Statement.readsClock`), the statement at the clock value is the statement. Proof
sketch: each expression that {name}`Statement.atClock` changes is one that
{name}`Statement.readsClock` checks, and the lemmas above keep it. -/
theorem Statement.atClock_of_readsClock (clock : Int) (statement : Statement) (free : statement.readsClock = false) :
    statement.atClock clock = statement := by
  cases statement with
  | insert at_ rows keys returning =>
    simp [Statement.atClock, Statement.expressionsAtClock, returningAtClock_of_readsClock _ _ free]
  | upsert at_ rows clauses keys returning policy =>
    simp only [Statement.readsClock, Bool.or_eq_false_iff] at free
    simp [Statement.atClock, Statement.expressionsAtClock, clauses_atClock _ _ free.1,
      returningAtClock_of_readsClock _ _ free.2]
  | update at_ assignments filter keys returning =>
    simp only [Statement.readsClock, Bool.or_eq_false_iff] at free
    simp [Statement.atClock, Statement.expressionsAtClock, assignments_atClock _ _ free.1.1,
      option_atClock _ _ free.1.2, returningAtClock_of_readsClock _ _ free.2]
  | delete at_ filter returning =>
    simp only [Statement.readsClock, Bool.or_eq_false_iff] at free
    simp [Statement.atClock, Statement.expressionsAtClock, option_atClock _ _ free.1,
      returningAtClock_of_readsClock _ _ free.2]
  | query inner => simp [Statement.atClock, Statement.expressionsAtClock, Query.atClock_of_readsClock _ _ free]
  | clocked => simp [Statement.readsClock] at free
  | createTable | createIndex | addColumn | begin | commit | rollback | prepareError =>
    rfl

end Belay.Sqlite.Resolved
