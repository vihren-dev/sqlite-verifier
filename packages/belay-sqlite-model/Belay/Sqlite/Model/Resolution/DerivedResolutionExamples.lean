import Belay.Sqlite.Model.Resolution.CompoundResolutionExamples

set_option doc.verso true

/-! Kernel checks of derived-table resolution through evaluation (ADR 0019, D5).
These examples cover source names, enclosing scope, preparation order and full-row certainty.
The text and native conformance suites exercise the same forms through SQL translation. -/

namespace Belay.Sqlite.Model.Resolution.DerivedResolutionExamples

open Syntax Resolution.Examples Resolution.CollationExamples Resolution.CompoundResolutionExamples

/-- A derived source whose SELECT is in the statement's indexed query list. -/
def derived (index : Nat) (alias : Option String := none) : TableReference :=
  { table := name! "", alias := alias.map Identifier.ofString, query := some index }

/-- A statement that reads one derived source, with arbitrary output expressions. -/
def fromDerived (columns : List ResultColumn) (subqueries : List Subquery) : Syntax.Statement :=
  .select columns (some (derived 0 (some "d"))) [] none [] [] none none subqueries

/-- Every output column is expanded and qualified, and duplicate names receive SQLite suffixes. -/
example : namesOf (fromDerived [.sourceStar (name! "d")]
    [term [named (num "1") "x", named (num "2") "x", named (num "3") "x"]]) =
    some ["x", "x:1", "x:2"] := by decide +kernel

/-- A qualified second column reads the correct source cell. -/
example : rowsOf (fromDerived [shown (.qualified (name! "d") (name! "y"))]
    [term [named (num "1") "x", named (num "2") "y"]]) = some [[.integer 2]] := by decide +kernel

/-- Derived output has no implicit rowid. -/
example : errorOf (fromDerived [shown (ref (name! "rowid"))] [term [named (num "1") "x"]]) =
    some (.expression (.noSuchColumn (name! "rowid"))) := by decide +kernel

/-- A derived table cannot read a sibling FROM table as a lateral binding. -/
example : errorOf (.select [.star] (some { table := name! "t", alias := none })
    [{ operator := [], source := derived 0, condition := none, usingColumns := none }]
    none [] [] none none [term [shown (.qualified (name! "t") (name! "a"))]]) =
    some (.expression (.noSuchColumn (name! "t.a"))) := by decide +kernel

/-- A derived table inside an expression subquery can read the statement's enclosing table. -/
example : rowsOf (.select [shown (.subquery 0)] (some { table := name! "t", alias := none })
    [] none [] [] none none
    [{ term [shown (ref (name! "x"))] with source := some (derived 1) },
     term [named (.qualified (name! "t") (name! "a")) "x"] none (some 0)]) =
    some [[.text [49]]] := by decide +kernel

/-- Expanding source tables precedes resolving expressions in a derived source. -/
example : errorOf (.select [.star] (some (derived 0))
    [{ operator := [], source := { table := name! "absent", alias := none }, condition := none, usingColumns := none }]
    none [] [] none none [term [shown (ref (name! "missing"))] (some "t")]) =
    some (.noSuchTable (name! "absent")) := by decide +kernel

/-- Derived bodies resolve in FROM order even when their indexes are reversed. -/
example : errorOf (.select [.star] (some (derived 1))
    [{ operator := [], source := derived 0, condition := none, usingColumns := none }]
    none [] [] none none [term [shown (ref (name! "second"))], term [shown (ref (name! "first"))]]) =
    some (.expression (.noSuchColumn (name! "first"))) := by decide +kernel

/-- Scalar siblings resolve in their written order, before the containing body's missing name. -/
example : errorOf (.select [shown (.subquery 0), shown (.subquery 1), shown (ref (name! "outer"))]
    none [] none [] [] none none
    [term [shown (ref (name! "first"))], term [shown (ref (name! "second"))]]) =
    some (.expression (.noSuchColumn (name! "first"))) := by decide +kernel

/-- An aggregate source supplies its one result row. -/
example : rowsOf (fromDerived [.star] [term [named (.callStar "count") "n"] (some "w")]) =
    some [[.integer 2]] := by decide +kernel

/-- A source with plan-sensitive LIMIT membership is refused by the existing evaluator. -/
example : rowsOf (fromDerived [.star] [{ term [.star] (some "w") with limit := some (num "1") }]) =
    none := by decide +kernel

/-- LIMIT zero has a certain empty source even without an ordering. -/
example : rowsOf (fromDerived [.star] [{ term [.star] (some "w") with limit := some (num "0") }]) =
    some [] := by decide +kernel

/-- A nested USING equality is rebuilt with its derived left column's NOCASE collation. -/
example : rowsOf (.select [shown (.subquery 0)] none [] none [] [] none none
    [{ term [shown (.callStar "count")] with
       source := some (derived 1), joins := [{ operator := [], source := derived 2, condition := none, usingColumns := some [name! "x"] }] },
     term [named (.collate (.string [97]) (name! "nocase")) "x"] none (some 0),
     term [named (.string [65]) "x"] none (some 0)]) = some [[.integer 1]] := by decide +kernel

end Belay.Sqlite.Model.Resolution.DerivedResolutionExamples
