import Lean.Meta.Tactic.Simp.RegisterCommand

set_option doc.verso true

/-! The simp attribute {lit}`sql_simp` (ADR 0017, S4). The model package imports only Lean's
prelude, so the attribute is registered here, in the surface, and {lit}`Belay/Sqlite/SqlSimpLaws.lean`
puts the model's laws in it. -/

namespace Belay.Sqlite

register_simp_attr sql_simp

end Belay.Sqlite
