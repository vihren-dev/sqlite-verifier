import Belay.Sqlite.Model.SimpleSourceResolution

set_option doc.verso true

/-! The resolution of the expressions of a condition (ADR 0017, S4): for the forms of a condition that
compares columns, parameters and numbers, the equation of the resolver ({lit}`resolveOperand`) for the form,
written so that {lit}`simp` rewrites the parts in place: a comparison is the comparison of its two
resolved operands, the name of a column of a table is the column at its position, and a written number is its
value. Each law says which issue the resolver gives when a part has an issue, or says that the law covers
the success case only. -/

namespace Belay.Sqlite.Model

variable {dqs : Bool} {scope : Scope} {shapes : SubqueryShapes} {misuse : Bool}

/-- NULL resolves to the NULL literal without affinity. Proof sketch: the definition computes. -/
theorem resolveOperand_null :
    resolveOperand dqs scope shapes misuse .null = .ok (.literal .null, none) := rfl

/-- A string literal resolves to the text literal of its bytes, without affinity. Proof sketch: the
definition computes. -/
theorem resolveOperand_string (bytes : List UInt8) :
    resolveOperand dqs scope shapes misuse (.string bytes) = .ok (.literal (.text bytes), none) := rfl

/-- Parameter {lit}`number` resolves to the parameter, without affinity. Proof sketch: the
definition computes. -/
theorem resolveOperand_parameter (number : Nat) :
    resolveOperand dqs scope shapes misuse (.parameter number) = .ok (.parameter number, none) := rfl

/-- A numeric literal resolves to its value ({name}`queryNumeric`), without affinity. A hexadecimal literal
outside 64 bits resolves to the issue that {name}`queryNumeric` gives ({lit}`hex literal too big`). Unfolding {name}`queryNumeric` computes the value of a written literal.
Proof sketch: the definition of the resolver. -/
theorem resolveOperand_numeric (text : String) :
    resolveOperand dqs scope shapes misuse (.numeric text) =
      (queryNumeric text false).map fun value => (.literal value, none) := rfl

/-- A negated numeric literal resolves to its negated value ({name}`queryNumeric`), without
affinity; a hexadecimal literal outside 64 bits, also after negation, resolves to the issue that
{name}`queryNumeric` gives. Proof sketch: the definition of the resolver. -/
theorem resolveOperand_negate_numeric (text : String) :
    resolveOperand dqs scope shapes misuse (.negate (.numeric text)) =
      (queryNumeric text true).map fun value => (.literal value, none) := rfl

/-- The columns of the scope of one source are the columns of the source. Proof sketch: the
definitions compute. -/
theorem Scope.columns_single (source : Identifier) (columns : List CatalogColumn) (hasRowid : Bool) :
    (Scope.single source columns hasRowid).columns = columns := by
  simp [Scope.columns, Scope.single]

/-- In the scope of one source, an unqualified name that names the column at position {lit}`index`
resolves to that column alone. Proof sketch: the scope has one source at depth 0 that is no
trigger's row, so the name resolves to the first column of the name in it
({name}`Scope.resolveStep`). -/
theorem resolveName_one_source {name : Identifier} {source : Identifier} {columns : List CatalogColumn}
    {hasRowid : Bool} {index : Nat} (found : columnPosition columns name = some index) :
    (Scope.single source columns hasRowid).resolveName name = .found index [index] := by
  simp [Scope.resolveName, Scope.depths, Scope.single, Scope.resolveAt, Scope.resolveStep, found]

/-- In the scope of one source, an unqualified name that names the column at position {lit}`index`
resolves to that column, with the affinity of the column. The law covers a name that the scope finds; the
resolver gives an issue for a name that it does not find. Proof sketch: the name resolves to the
column alone ({name}`resolveName_one_source`), and no cell of the source is an argument cell or a
trigger cell. -/
theorem resolveOperand_identifier_single {name : Identifier} {quote : Syntax.QuoteKind} {source : Identifier}
    {columns : List CatalogColumn} {hasRowid : Bool} {index : Nat} (found : columnPosition columns name = some index) :
    resolveOperand dqs (Scope.single source columns hasRowid) shapes misuse (.identifier name quote) =
      .ok (.column index, columns[index]?.map CatalogColumn.affinity) := by
  simp only [resolveOperand, resolveName_one_source found]
  simp [Scope.nameRead, Scope.nameOperand, Scope.single, Scope.argumentCell, Scope.triggerCell, Scope.columns]

/-- A name of a column of the table at a catalog position resolves to the column at its position,
with its affinity. The law covers a name that the table has; the resolver gives an issue for a name that it
does not find. Proof sketch: {name}`tableScope` is the scope of one source, so this is
{name}`resolveOperand_identifier_single`. -/
theorem resolveOperand_identifier_table {catalog : Catalog} {reference : Syntax.TableReference}
    {position : Nat} {table : CatalogTable} {name : Identifier} {quote : Syntax.QuoteKind} {index : Nat}
    (found : columnPosition table.columns name = some index) :
    resolveOperand dqs (tableScope catalog reference position table) shapes misuse (.identifier name quote) =
      .ok (.column index, table.columns[index]?.map CatalogColumn.affinity) :=
  resolveOperand_identifier_single found

/-- A comparison other than {lit}`IS` and {lit}`IS NOT` resolves its two operands, left first, and
compares them with the affinity {name}`comparisonAffinity` of the two and the collation
{name}`comparisonCollation` of the written operands; it has no affinity. If the left operand has an issue, the
result is that issue under position 1 and the right operand is not resolved; otherwise, if the right operand has
an issue, the result is that issue under position 2. The law is an equation of the resolver, so {lit}`simp` rewrites the
operands in place. Proof sketch: unfold the resolver; the operator is no truth test
({name}`truthTest`) because it is neither {lit}`IS` nor {lit}`IS NOT`. -/
theorem resolveOperand_compare {operator : Comparison} (left right : Syntax.Expr)
    (notIs : operator ≠ .is) (notIsNot : operator ≠ .isNot) :
    resolveOperand dqs scope shapes misuse (.compare operator left right) = (do
      let a ← (resolveOperand dqs scope shapes misuse left).mapError (·.under [1])
      let b ← (resolveOperand dqs scope shapes misuse right).mapError (·.under [2])
      .ok (.compare operator (comparisonAffinity a.2 b.2) a.1 b.1 (comparisonCollation scope left right), none)) := by
  have plain : ∀ b : Resolved.Expr, truthTest operator right b = false := by
    intro b
    cases operator <;> simp_all [truthTest]
  simp [resolveOperand, plain]

/-- {lit}`x COLLATE c` with a collation name that the model knows resolves as {lit}`x` does, and an
issue of {lit}`x` is under position 0. A collation name that the model does not know is not covered. Proof
sketch: unfold the resolver; the name gives a collation. -/
theorem resolveOperand_collate (operand : Syntax.Expr) {name : Identifier}
    (known : (Collation.named? name).isNone = false) :
    resolveOperand dqs scope shapes misuse (.collate operand name) =
      (resolveOperand dqs scope shapes misuse operand).mapError (·.under [0]) := by
  simp [resolveOperand, known, Bind.bind, Except.bind]
  cases resolveOperand dqs scope shapes misuse operand <;> rfl

/-- {lit}`x AND y` resolves both operands as conditions and is the {lit}`AND` of the two
expressions, without affinity. An issue of the left operand is under position 0 and an issue of the right
operand under position 1; the left operand is resolved first. Proof sketch: the definition of the resolver. -/
theorem resolveOperand_and (left right : Syntax.Expr) :
    resolveOperand dqs scope shapes misuse (.and left right) = (do
      let a ← condition [0] (resolveOperand dqs scope shapes misuse left)
      let b ← condition [1] (resolveOperand dqs scope shapes misuse right)
      .ok (.and a b, none)) := by
  simp [resolveOperand]

/-- {lit}`x OR y` resolves both operands as conditions and is the {lit}`OR` of the two
expressions, without affinity. An issue of the left operand is under position 0 and an issue of the right
operand under position 1; the left operand is resolved first. Proof sketch: the definition of the resolver. -/
theorem resolveOperand_or (left right : Syntax.Expr) :
    resolveOperand dqs scope shapes misuse (.or left right) = (do
      let a ← condition [0] (resolveOperand dqs scope shapes misuse left)
      let b ← condition [1] (resolveOperand dqs scope shapes misuse right)
      .ok (.or a b, none)) := by
  simp [resolveOperand]

/-- {lit}`NOT x` resolves its operand as a condition and is the {lit}`NOT` of the expression,
without affinity. An issue of the operand is under position 0. Proof sketch: the definition of the resolver. -/
theorem resolveOperand_not (operand : Syntax.Expr) :
    resolveOperand dqs scope shapes misuse (.not operand) = (do
      let a ← condition [0] (resolveOperand dqs scope shapes misuse operand)
      .ok (.not a, none)) := by
  simp [resolveOperand]

/-- {lit}`x IS NULL` and {lit}`x IS NOT NULL` resolve the operand and test the expression, without
affinity. An issue of the operand is under position 0. Proof sketch: the definition of the resolver. -/
theorem resolveOperand_isNull (operand : Syntax.Expr) (negated : Bool) :
    resolveOperand dqs scope shapes misuse (.isNull operand negated) = (do
      let a ← (resolveOperand dqs scope shapes misuse operand).mapError (·.under [0])
      .ok (.isNull a.1 negated, none)) := by
  simp [resolveOperand]

/-- {lit}`x BETWEEN low AND high` resolves the three operands and is {lit}`x >= low AND x <= high`,
each comparison with its own affinity and collation. The operands are resolved in the order {lit}`x`,
low, high, and the first issue is under position 0, 1 or 2 respectively. Proof sketch: the definition of the
resolver. -/
theorem resolveOperand_between (operand low high : Syntax.Expr) :
    resolveOperand dqs scope shapes misuse (.between operand low high false) = (do
      let a ← (resolveOperand dqs scope shapes misuse operand).mapError (·.under [0])
      let l ← (resolveOperand dqs scope shapes misuse low).mapError (·.under [1])
      let h ← (resolveOperand dqs scope shapes misuse high).mapError (·.under [2])
      .ok (.and (.compare .ge (comparisonAffinity a.2 l.2) a.1 l.1 (comparisonCollation scope operand low))
        (.compare .le (comparisonAffinity a.2 h.2) a.1 h.1 (comparisonCollation scope operand high)), none)) := by
  simp [resolveOperand]

/-- {lit}`x NOT BETWEEN low AND high` is the {lit}`NOT` of {lit}`x BETWEEN low AND high`
({name}`resolveOperand_between`), with the same issues. Proof sketch: the definition of the resolver. -/
theorem resolveOperand_not_between (operand low high : Syntax.Expr) :
    resolveOperand dqs scope shapes misuse (.between operand low high true) = (do
      let a ← (resolveOperand dqs scope shapes misuse operand).mapError (·.under [0])
      let l ← (resolveOperand dqs scope shapes misuse low).mapError (·.under [1])
      let h ← (resolveOperand dqs scope shapes misuse high).mapError (·.under [2])
      .ok (.not (.and (.compare .ge (comparisonAffinity a.2 l.2) a.1 l.1 (comparisonCollation scope operand low))
        (.compare .le (comparisonAffinity a.2 h.2) a.1 h.1 (comparisonCollation scope operand high))), none)) := by
  simp [resolveOperand]

/-- A {lit}`WHERE` term that names no alias and resolves to an operand resolves to the expression of
the operand, as {name}`FilterResolves` says. Proof sketch: the second disjunct of the definition. -/
theorem FilterResolves.of_term {aliases : List Identifier} {term : Syntax.Expr} {result : Operand}
    (noAlias : namesAlias scope aliases term = false)
    (resolved : resolveOperand dqs scope shapes true term = .ok result) :
    FilterResolves dqs scope aliases (some term) (some result.1) shapes :=
  Or.inr ⟨term, result.1, result.2, rfl, rfl, noAlias, by simpa using resolved⟩

/-- A query without {lit}`WHERE` has no condition, as {name}`FilterResolves` says. Proof sketch:
the first disjunct of the definition. -/
theorem FilterResolves.of_none (dqs : Bool) (scope : Scope) (aliases : List Identifier) (shapes : SubqueryShapes) :
    FilterResolves dqs scope aliases none none shapes :=
  Or.inl ⟨rfl, rfl⟩

end Belay.Sqlite.Model
