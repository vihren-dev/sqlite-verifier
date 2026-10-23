import Belay.Sqlite.Model

set_option doc.verso true

/-! The surface's scripts (ADR 0017, D3): a fixed list of statements, as in a {lit}`.sql` file,
each with the values bound to its parameters (ADR 0019, D1). Scripts form a monoid under
{lit}`++`, with {lit}`Script.empty` as its unit, and the append keeps each statement's values.
The term {lit}`sql r"..."` of {lit}`Belay/Sqlite/SqlTerm.lean` gives a script that binds no
values for a text without parameters, and otherwise {lit}`Script.withValues` of that script with
the values of the parameters. {lit}`Script.withValues` also binds values that the notation cannot
express. -/

namespace Belay.Sqlite

/-- SQL text as data: its statements in order, as the translation gives them, each with the
values bound to its parameters. For example, {lit}`sql r"COMMIT"` is the script of one
statement, {name}`Belay.Sqlite.Model.Syntax.Statement.commit`, with no values. -/
structure Script where
  /-- The statements, in the order of the text, each with the values bound to its parameters:
  item {lit}`n` (from 1) of the list is the value of parameter {lit}`n`, and a parameter without
  an item is NULL. -/
  statements : List (Belay.Sqlite.Model.Syntax.Statement × List Belay.Sqlite.Model.Value)

namespace Script

/-- The script without statements, the unit of {lit}`++`. For example,
{assert}`Script.empty.statements = []`. -/
def empty : Script := ⟨[]⟩

/-- The statements of the first script, then the statements of the second, each with its
values. -/
instance : Append Script := ⟨fun first second => ⟨first.statements ++ second.statements⟩⟩

/-- For all scripts {lit}`p` and {lit}`q`, the statements ({name}`Script.statements`) of
{lit}`p ++ q` are those of {lit}`p`, then those of {lit}`q`. For example,
{lean}`(Script.empty ++ Script.empty).statements = Script.empty.statements ++ Script.empty.statements`.
Proof sketch: the definition of {lit}`++`. -/
@[simp] theorem statements_append (p q : Script) : (p ++ q).statements = p.statements ++ q.statements := rfl

/-- For every script {lit}`p`, {name}`Script.empty` before {lit}`p` gives {lit}`p`. Proof sketch:
the lists are equal by definition. -/
@[simp] theorem empty_append (p : Script) : empty ++ p = p := rfl

/-- For every script {lit}`p`, {name}`Script.empty` after {lit}`p` gives {lit}`p`. Proof sketch:
the lists are equal ({name}`List.append_nil`). -/
@[simp] theorem append_empty (p : Script) : p ++ empty = p := by
  cases p
  show Script.mk (_ ++ []) = _
  rw [List.append_nil]

/-- For all scripts {lit}`p`, {lit}`q` and {lit}`r`, {lit}`(p ++ q) ++ r` is {lit}`p ++ (q ++ r)`,
so a chain needs no parentheses. Proof sketch: list append is associative
({name}`List.append_assoc`). -/
theorem append_assoc (p q r : Script) : p ++ q ++ r = p ++ (q ++ r) := by
  cases p; cases q; cases r
  show Script.mk (_ ++ _ ++ _) = Script.mk (_ ++ (_ ++ _))
  rw [List.append_assoc]

/-- The script with the values bound to the parameters of its statements: statement {lit}`i`
(from 0) gets item {lit}`i` of {lit}`values`, or the empty list when {lit}`values` has no such
item, in place of the values that it had ({name}`Belay.Sqlite.Model.bindValues`). For example,
{lean}`(Script.empty.withValues [[.integer 1]]).statements = []`. The term {lit}`sql "..."` of a text with
parameters is this function of the script without values, so a script that the notation does
not give, such as one with a value list computed from data, uses it directly. -/
def withValues (script : Script) (values : List (List Belay.Sqlite.Model.Value)) : Script :=
  ⟨Belay.Sqlite.Model.bindValues (script.statements.map (·.1)) values⟩

/-- For every script and list of lists of values, {name}`Script.withValues` keeps the statements
of the script and changes only their values. Proof sketch:
{name}`Belay.Sqlite.Model.map_fst_bindValues`. -/
@[simp] theorem withValues_statements (script : Script) (values : List (List Belay.Sqlite.Model.Value)) :
    (script.withValues values).statements.map (·.1) = script.statements.map (·.1) :=
  Belay.Sqlite.Model.map_fst_bindValues _ values

end Script

end Belay.Sqlite
