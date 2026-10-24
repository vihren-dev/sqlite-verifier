import Belay.Sqlite.Model.ResolveNamesBelow

set_option doc.verso true

/-! The pieces of the CHECK lemma that do not recurse (ADR 0022, D3, slice 4): the expressions
that resolution builds from names and from resolved arguments read no column at or after a
width when the names and the arguments do not. {lit}`ResolveReadsBelow` combines them. In this
file "reads below the width" means that {lit}`Expr.any` of {lit}`Expr.isColumnFrom` for the
width is false. -/

namespace Belay.Sqlite.Model

open Resolved

/-- For every result of resolution that is bound to a continuation, and every value: the bind is
that value exactly when the first result is a value and the continuation gives the value from
it. Proof sketch: case analysis on the first result; an error stays an error. -/
theorem exceptBind_eq_ok {ε α β : Type} {first : Except ε α} {continuation : α → Except ε β} {result : β} :
    (first >>= continuation) = .ok result ↔ ∃ value, first = .ok value ∧ continuation value = .ok result := by
  cases first <;> simp [bind, Except.bind]

/-- For every result of resolution whose error changes, and every value: the result with the
changed error is that value exactly when the first result is that value. An error stays an
error. Proof sketch: case analysis on the first result. -/
theorem exceptMapError_eq_ok {ε ε' α : Type} {first : Except ε α} {change : ε → ε'} {value : α} :
    first.mapError change = .ok value ↔ first = .ok value := by
  cases first <;> simp [Except.mapError]

/-- For every result of resolution whose value changes, and every value: the changed result is
that value exactly when the first result is a value that changes into it. An error stays an
error. Proof sketch: case analysis on the first result. -/
theorem exceptMap_eq_ok {ε α β : Type} {first : Except ε α} {change : α → β} {result : β} :
    first.map change = .ok result ↔ ∃ value, first = .ok value ∧ change value = result := by
  cases first <;> simp [Except.map]

/-- For every result of resolution whose value changes with {lit}`<$>`: as
{name}`exceptMap_eq_ok`. Proof sketch: case analysis on the first result. -/
theorem exceptFmap_eq_ok {ε α β : Type} {first : Except ε α} {change : α → β} {result : β} :
    change <$> first = .ok result ↔ ∃ value, first = .ok value ∧ change value = result := by
  cases first <;> simp [Functor.map, Except.map]

/-- For every path, result of resolving an operand and expression: the condition of the result
is that expression exactly when the operand resolved to a value whose expression it is
({name}`condition`). Proof sketch: case analysis on the operand result; a value gives its
expression and an error stays an error. -/
theorem condition_eq_ok {path : List Nat} {operand : Except ValueIssue Operand} {expression : Expr} :
    condition path operand = .ok expression ↔ ∃ value, operand = .ok value ∧ value.1 = expression := by
  cases operand <;> simp [condition]

/-- For every width and positions that are all below it, the coalesce of the columns at the
positions reads below the width ({name}`coalesceColumns`). Proof sketch: induction over the
positions; each column is one of them. -/
theorem coalesceColumns_below {width : Nat} : ∀ {reads : List Nat}, (∀ position ∈ reads, position < width) →
    (coalesceColumns reads).any (Expr.isColumnFrom width) = false
  | [], _ => by simp [coalesceColumns, Expr.any, Expr.isColumnFrom]
  | [position], below => by
    have := below position (by simp)
    simp [coalesceColumns, Expr.any, Expr.isColumnFrom, this]
  | position :: next :: rest, below => by
    have head := below position (by simp)
    have tail := coalesceColumns_below (reads := next :: rest) fun p m => below p (List.mem_cons_of_mem _ m)
    simp [coalesceColumns, Expr.any, Expr.isColumnFrom, head, tail]

/-- For every scope, positions that are all below a width and operand: if the name that reads the
positions resolves to the operand ({name}`Scope.nameRead`), the operand reads below the width. A
name that is refused gives no operand and requires nothing. Proof sketch: a refused name gives no
operand; an accepted name is a column, which {lit}`below` bounds, or the coalesce of columns
({name}`coalesceColumns_below`). -/
theorem nameRead_below {width : Nat} {scope : Scope} {reads : List Nat} {operand : Operand}
    (below : ∀ position ∈ reads, position < width) (ok : scope.nameRead reads = .ok operand) :
    operand.1.any (Expr.isColumnFrom width) = false := by
  unfold Scope.nameRead at ok
  split at ok
  · cases ok
  · cases ok
    unfold Scope.nameOperand
    split
    · simp_all [Expr.any, Expr.isColumnFrom]
    · exact coalesceColumns_below below

/-- For every arguments that read below a width, the coalesce of them reads below the width
({name}`coalesceOf`). Proof sketch: induction over the arguments. -/
theorem coalesceOf_below {width : Nat} : ∀ {arguments : Arguments},
    arguments.any (Expr.isColumnFrom width) = false → (coalesceOf arguments).any (Expr.isColumnFrom width) = false
  | .nil, _ => by simp [coalesceOf, Expr.any, Expr.isColumnFrom]
  | .cons _ .nil, h => by simpa [coalesceOf, Arguments.any, Expr.any] using h
  | .cons head (.cons next rest), h => by
    have := coalesceOf_below (width := width) (arguments := .cons next rest) (by simp_all [Arguments.any])
    simp only [Arguments.any, Bool.or_eq_false_iff] at h
    simp [coalesceOf, Expr.any, Expr.isColumnFrom, h.1, this]

/-- For every arguments that read below a width, the first of them reads below the width
({name}`Resolved.Arguments.first`). Proof sketch: the first argument is NULL or a part of the
arguments. -/
theorem first_below {width : Nat} : ∀ {arguments : Arguments},
    arguments.any (Expr.isColumnFrom width) = false → arguments.first.any (Expr.isColumnFrom width) = false
  | .nil, _ => by simp [Arguments.first, Expr.any, Expr.isColumnFrom]
  | .cons _ _, h => by simp_all [Arguments.first, Arguments.any]

/-- For every function, name and arguments that read below a width: if the JSON call resolves to
an operand, the operand reads below the width ({name}`jsonCall`). A refused call requires
nothing. Proof sketch: an accepted call is the JSON expression over the arguments, which read
below the width. -/
theorem jsonCall_below {width : Nat} {name function arguments operand}
    (below : arguments.any (Expr.isColumnFrom width) = false)
    (ok : jsonCall name function arguments = .ok operand) : operand.1.any (Expr.isColumnFrom width) = false := by
  unfold jsonCall at ok
  split at ok
  · cases ok
  split at ok
  · cases ok
  · cases ok
    simp_all [Expr.any, Expr.isColumnFrom]

/-- For every scope, name, written arguments and resolved arguments that read below a width: if
the scalar call resolves to an operand, the operand reads below the width
({name}`scalarCall`). A refused call requires nothing. Proof sketch: every function that the
call can name builds its expression from the arguments alone, with {name}`coalesceOf_below`,
{name}`first_below` or {name}`jsonCall_below` for the calls that change them. -/
theorem scalarCall_below {width : Nat} {scope name written arguments operand}
    (below : arguments.any (Expr.isColumnFrom width) = false)
    (ok : scalarCall scope name written arguments = .ok operand) : operand.1.any (Expr.isColumnFrom width) = false := by
  have coalesced := coalesceOf_below below
  have firsts := first_below below
  unfold scalarCall at ok
  repeat' split at ok
  all_goals dsimp only at ok
  all_goals first
    | (cases ok; done)
    | (cases ok; simp_all [Expr.any, Expr.isColumnFrom]; done)
    | (exact jsonCall_below below ok)

/-- For every scope, name, written arguments and resolved arguments that read below a width: if
the call resolves to an operand, the operand reads below the width ({name}`callOperand`). A
refused call requires nothing. Proof sketch: the checks of the name and of the number of
arguments only refuse; the call then is {name}`scalarCall_below`. -/
theorem callOperand_below {width : Nat} {scope misuse name written arguments operand}
    (below : arguments.any (Expr.isColumnFrom width) = false)
    (ok : callOperand scope misuse name written arguments = .ok operand) :
    operand.1.any (Expr.isColumnFrom width) = false := by
  unfold callOperand at ok
  repeat' split at ok
  all_goals first
    | (cases ok; done)
    | exact scalarCall_below below ok

end Belay.Sqlite.Model
