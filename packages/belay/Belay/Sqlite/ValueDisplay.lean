import Lean.PrettyPrinter.Delaborator.Basic
import Belay.Sqlite.Model

set_option doc.verso true

/-! How a value shows in text and in the editor, as a user writes it: {lit}`s!"{v}"` and
{lit}`IO.println` show the literal of {lit}`Value.display`, for example {lit}`3` and
{lit}`"acme"`; and Lean shows an INTEGER value of a natural number as its number, as the
literal {lit}`(3 : Value)` gives it. So {lit}`#eval run.value` of a run with the value
{lit}`some (some (.integer 3))` shows {lit}`some (some 3)`. -/

namespace Belay.Sqlite

open Belay.Sqlite.Model Lean PrettyPrinter

/-- A value as the literal that gives it ({name}`Belay.Sqlite.Model.Value.display`). For
example, {lean}`toString (Value.integer 3) = "3"`. -/
instance : ToString Value := ⟨fun value => toString value.display⟩

/-- Show {lit}`Value.integer n` of a natural number literal {lit}`n` as {lit}`n`, the literal that
gives it ({lit}`OfNat Value`). Lean shows each other value with its constructor. -/
@[app_unexpander Belay.Sqlite.Model.Value.integer]
def unexpandIntegerValue : Unexpander
  | `($_ $number:num) => `($number:num)
  | _ => throw ()

end Belay.Sqlite
