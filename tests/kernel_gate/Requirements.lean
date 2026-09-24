import SqliteVerifier

/-! Small honest contract used only to exercise the kernel gate. -/
namespace Requirements
/-- Fixed logical state for the no-op test. -/
abbrev LogicalState := Unit
/-- Unrestrictive observations leave schema conformance as the concrete obligation. -/
def contract : SqliteVerifier.LogicalContract LogicalState :=
  ⟨fun _ => True, fun _ _ => True, fun _ => True,
   fun _ _ _ _ => True, fun _ _ => True⟩
end Requirements
