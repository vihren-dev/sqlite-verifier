import Belay.Sqlite.Model.ResolveCreateTableCatalog
import Belay.Sqlite.Model.Resolution.Examples

set_option doc.verso true

/-! Examples of the resolver facts of the Admitted atoms (ADR 0022, slice 4, part 1), each checked
by the kernel. CREATE TABLE of a table with a key that names a column twice, or a CHECK that names a
column of the table, gives a valid catalog; and each invariant of the proof (a rowid alias column,
the shape of the keys, a draft, a table that is building a column) holds for a table that has it and
fails for a table that has not. -/

namespace Belay.Sqlite.Model.AdmittedAtomsResolverExamples

open Belay.Sqlite.Model Resolution.Examples Syntax

/-- The context of a script that runs. -/
def execution : ResolveContext := { profile := defaults, mode := .execution }

/-- CREATE TABLE {lit}`t(a INTEGER, b TEXT, ...constraints)` in the empty catalog. -/
def createT (constraints : List TableConstraint) : StatementResolution :=
  resolveCreateTable execution [] (name! "t") [column (name! "a") (some "INTEGER"), column (name! "b")] constraints

/-- Whether the resolution gives a catalog that is supported under the limits. -/
def validAfter : StatementResolution → Bool
  | .ok (_, catalog) => catalog.supported defaults.limits
  | .error _ => false

-- A key may name a column twice, and a CHECK may name a column of the table.
example : validAfter (createT [.primaryKey [name! "a", name! "a"]]) = true := by decide +kernel
example : validAfter (createT [.unique [name! "b", name! "b"]]) = true := by decide +kernel
example : validAfter (createT [.check (.identifier (name! "b") .none) ""]) = true := by decide +kernel
-- A key that names a missing column is a prepare error, which leaves the catalog as it was.
example : validAfter (createT [.primaryKey [name! "c"]]) = true := by decide +kernel
-- An empty key list is refused as SQLite does, and the catalog stays empty.
example : (match createT [.primaryKey []] with | .ok (_, catalog) => catalog.length | .error _ => 1) = 0 := by
  decide +kernel

/-- A hypothesis-free use of the theorem: the catalog after the CREATE TABLE of the first example. -/
example (statement : Resolved.Statement) (after : Catalog)
    (ok : createT [.primaryKey [name! "a", name! "a"]] = .ok (statement, after)) : after.Valid defaults.limits :=
  resolveCreateTable_valid execution [] after _ _ _ _ statement (by decide +kernel) rfl ok

/-- The columns {lit}`a INTEGER, b TEXT`. -/
def twoColumns : List CatalogColumn :=
  [{ name := name! "a", declaredType := some "INTEGER" }, { name := name! "b", declaredType := some "TEXT" }]

-- The layout of a column is its name, declared type, strict type and generated flag.
example : (twoColumns.map CatalogColumn.layout) = [(name! "a", some "INTEGER", none, false), (name! "b", some "TEXT", none, false)] := rfl
example : (twoColumns.map CatalogColumn.typing) = [(none, some "INTEGER"), (none, some "TEXT")] := rfl

-- A rowid alias column is a column of INTEGER affinity that is not generated.
example : AliasColumn twoColumns 0 := ⟨_, rfl, rfl, by decide +kernel⟩
example : ¬ AliasColumn twoColumns 1 := by
  rintro ⟨column, found, _, integer⟩
  simp only [twoColumns, List.getElem?_cons_succ, List.getElem?_cons_zero, Option.some.injEq] at found
  subst found
  revert integer
  decide +kernel

-- A STRICT ANY column has the declared type ANY.
example : AnyDeclared [{ name := name! "a", declaredType := some "ANY", strictType := some .any }] := by
  intro column member strict
  simp only [List.mem_singleton] at member
  subst member
  rfl
example : ¬ AnyDeclared [{ name := name! "a", declaredType := some "TEXT", strictType := some .any }] := by
  intro declared
  have := declared _ (List.mem_singleton.mpr rfl) rfl
  simp at this

/-- The table {lit}`t(a INTEGER PRIMARY KEY, b TEXT)`. -/
def keyed : CatalogTable := { columns := twoColumns, primaryKey := [0], rowidAlias := some 0 }

-- The shape of a table: keys inside the columns, unique folded names, and an alias that is the key.
/-- The table {name}`keyed` has the shape of {name}`CatalogTable.Shaped`: its primary key is inside the
columns, it has no UNIQUE key, its folded names are unique, and its alias is the whole primary key on an
alias column. Proof sketch: the clauses are about the one-position primary key, which is inside the two
columns, and the alias column, which the kernel checks. -/
theorem keyedShaped : keyed.Shaped :=
  ⟨by intro position member; simp only [keyed, List.mem_singleton] at member; subst member; decide,
   by intro key member; simp [keyed] at member,
   by decide +kernel,
   by intro position found; simp only [keyed, Option.some.injEq] at found; subst found;
      exact ⟨rfl, _, rfl, rfl, by decide +kernel⟩⟩
example : ¬ ({ keyed with primaryKey := [2], rowidAlias := none } : CatalogTable).Shaped := fun shaped =>
  absurd (shaped.primaryKey 2 (by simp)) (by simp [keyed, twoColumns])

-- A draft is shaped and not WITHOUT ROWID, and a strict ANY column of it is declared ANY.
/-- The table {name}`keyed` is a {name}`CatalogTable.Draft`. Proof sketch: it is shaped
({name}`keyedShaped`), it has a rowid, and none of its columns has the strict type ANY. -/
theorem keyedDraft : keyed.Draft :=
  ⟨keyedShaped, rfl, by intro column member strict; simp [keyed, twoColumns] at member; rcases member with rfl | rfl <;> simp at strict⟩
example : ¬ ({ keyed with withoutRowid := true } : CatalogTable).Draft := fun draft => by
  have := draft.ordinary; simp at this

-- The draft is building the column `b TEXT` when its last column is declared TEXT, and not the column
-- `a INTEGER`. A change that keeps the layout of the last column keeps the building.
/-- The table {name}`keyed` is building the column {lit}`b TEXT`, because its last column is declared TEXT. -/
theorem keyedBuilding : keyed.Building (column (name! "b") (some "TEXT")) := ⟨keyedDraft, by decide +kernel⟩
example : ¬ keyed.Building (column (name! "a") (some "INTEGER")) := fun building => by
  have := building.2; revert this; decide +kernel
example : CatalogTable.BuildStep (column (name! "b") (some "TEXT")) keyed
    { keyed with columns := updateLast keyed.columns fun column => { column with notNull := true } } :=
  CatalogTable.BuildStep.of_updateLast keyedBuilding _ fun _ => rfl

end Belay.Sqlite.Model.AdmittedAtomsResolverExamples
