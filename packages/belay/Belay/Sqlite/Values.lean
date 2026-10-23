import Belay.Sqlite.Model

set_option doc.verso true

/-! The surface's values (ADR 0017, D3): the model's {lit}`Value` with SQLite's five storage
classes, its comparison, truth and storage with their lemmas, and the coercions from Lean
literals. Each name is the model's declaration, given again under {lit}`Belay.Sqlite`, so that
{lit}`open Belay.Sqlite` finds it. -/

namespace Belay.Sqlite

export Belay.Sqlite.Model (Value Value.null Value.integer Value.real Value.text Value.blob
  Value.compare Value.compare_null Value.truth Value.truth_eq_true Value.truth_and Value.truth_or
  Value.truth_not Value.and Value.or Value.not Value.store Value.store_integer_text Value.store_store
  Value.store_null Truth Truth.true Truth.false Truth.unknown Truth.and Truth.or Truth.not Affinity)

/-- An integer literal is an INTEGER value. For example, {lean}`(10 : Value)` is
{lean}`Value.integer 10`. -/
instance (n : Nat) : OfNat Value n := ⟨.integer n⟩

/-- A string is a TEXT value with its UTF-8 bytes. For example, {lean}`(("acme" : String) : Value)`
is the TEXT {lit}`'acme'`. -/
instance : Coe String Value := ⟨fun text => .text text.toUTF8.toList⟩

/-- A Lean {lean}`Int64` is the INTEGER value of {lean}`Int64.toInt`, so a parameter {lit}`$id` of a
variable {lit}`id : Int64` binds an INTEGER. For example, {lean}`((-3 : Int64) : Value)` is
{lean}`Value.integer (-3)`. -/
instance : Coe Int64 Value := ⟨fun n => .integer n.toInt⟩

/-- A decimal literal is a REAL value with the bits of the nearest double. For example,
{lean}`(2.5 : Value)` is the REAL 2.5. -/
instance : OfScientific Value := ⟨fun mantissa negative exponent =>
  .real (OfScientific.ofScientific mantissa negative exponent : Float).toBits⟩

end Belay.Sqlite
