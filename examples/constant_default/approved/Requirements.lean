import SqliteVerifier.Library

set_option doc.verso true

/-! Preserve every invoice amount and require the declared priority default. -/
namespace Requirements
open Belay.Sqlite SqliteVerifier

/-- Each invoice rowid and amount remains a protected observation. -/
abbrev LogicalState := LogicalRows

/-- Existing invoice amount, whose values remain unchanged. -/
def amount : CatalogColumn := { name := "amount", declaredType := some "INTEGER" }

/-- Required priority initialized to seven; the written default is retained. -/
def priority : CatalogColumn := {
  name := "priority", declaredType := some "INTEGER"
  notNull := true, defaultValue := some ⟨.numeric "7", "7"⟩ }

/-- For every starting and resulting observation, success preserves all rowids and
amounts and requires the amount and priority columns with their exact metadata.
Failure must preserve the observation, but applicability requires success. -/
def contract : LogicalContract LogicalState where
  valid := fun _ => True
  change := Eq
  catalogRequirement catalog := catalog.columnsOf "invoices" = some [amount, priority]
  failure := fun before _ _ after => before = after
  applicability := requiresSuccess

end Requirements
