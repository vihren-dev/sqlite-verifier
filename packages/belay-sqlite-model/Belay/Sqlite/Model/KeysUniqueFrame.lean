import Belay.Sqlite.Model.DatabaseConstraints
import Belay.Sqlite.Model.DatabaseLaws
import Belay.Sqlite.Model.Execution

set_option doc.verso true

/-! The frame of the atom "keys unique" (ADR 0022, D3, slice 2): which databases of an effect the
theorems of the statements are about ({lit}`Effect.KeysUnique`), the frame lemma, and the lemmas
of a write that stores rows at one position. The theorems for each statement form use them. -/

namespace Belay.Sqlite.Model

/-- For the given effect: every database that a run can keep from it satisfies
{name}`Database.KeysUnique`. These are two cases:
* the effect succeeds with the database;
* the effect fails with {name}`ExecutionError.constraintFail` and carries the database, which
  keeps the rows that a FAIL write stored before the failed row.

An error with any other reason requires nothing: the run keeps the input database, or the
snapshot of a ROLLBACK, for it ({lit}`SqlState.publish`). -/
def Effect.KeysUnique (effect : Effect) : Prop :=
  ∀ database, effect = .ok database ∨ effect = .error (.constraintFail, database) → database.KeysUnique

/-- For every effect: if the database of the effect ({name}`effectDatabase`) satisfies
{name}`Database.KeysUnique`, the effect satisfies {name}`Effect.KeysUnique`. Proof sketch: both
databases of {name}`Effect.KeysUnique` are the database of the effect. -/
theorem Effect.keysUnique_of_effectDatabase {effect : Effect} (unique : (effectDatabase effect).KeysUnique) :
    effect.KeysUnique := by
  intro database kept
  rcases kept with same | same <;> subst same <;> exact unique

/-- For every database: if it satisfies {name}`Database.KeysUnique`, an effect that keeps it
on success or on every error satisfies {name}`Effect.KeysUnique`. This is the case of each
statement that writes no row. Proof sketch: {name}`Effect.keysUnique_of_effectDatabase` after
rewriting the database of the effect. -/
theorem Effect.keysUnique_of_database {effect : Effect} {database : Database} (unique : database.KeysUnique)
    (kept : effectDatabase effect = database) : effect.KeysUnique :=
  Effect.keysUnique_of_effectDatabase (kept ▸ unique)

/-- The frame lemma for one table, for every two lists of keys and two tables: if the first
table satisfies {name}`Table.KeysUnique` for the first keys, the second table has the same rows,
and each key of the second list is in the first list, then the second table satisfies
{name}`Table.KeysUnique` for the second keys. The catalog entries of the tables can differ:
the atom reads only the rows and the keys. Proof sketch: each key of the second list is a key of
the first, and the rows are the same. -/
theorem Table.KeysUnique.frame {keys kept : List UniqueKey} {table other : Table} (unique : table.KeysUnique keys)
    (rows : other.rows = table.rows) (subset : ∀ key ∈ kept, key ∈ keys) : other.KeysUnique kept :=
  fun key member => rows ▸ unique key (subset key member)

/-- The frame lemma for a table of a database, for every two databases, two positions and two
tables: if the first database satisfies {name}`Database.KeysUnique`, it has the first table at
the old position, the second table has the rows of the first, and each unique key of the new
position in the second catalog ({name}`Catalog.uniqueKeys`) is a unique key of the old position
in the first catalog, then the second table satisfies {name}`Table.KeysUnique` for the keys of
the new position in the second catalog. The second database need not have the table at the new
position; a statement that moves a table (DROP) and one that keeps it at its position use the
same lemma. Proof sketch: {name}`Table.KeysUnique.frame` of the atom at the old position. -/
theorem Database.KeysUnique.frame {before after : Database} (unique : before.KeysUnique) {position old : Nat}
    {table earlier : Table} (found : before.table old = some earlier) (rows : table.rows = earlier.rows)
    (keys : ∀ key ∈ after.catalog.uniqueKeys position table.shape, key ∈ before.catalog.uniqueKeys old earlier.shape) :
    table.KeysUnique (after.catalog.uniqueKeys position table.shape) :=
  (unique old earlier found).frame rows keys

/-- For every keys and two tables: if the first table satisfies {name}`Table.KeysUnique` for
the keys and the rows of the second are a sublist of the rows of the first, the second
satisfies it too. A DELETE stores such a sublist. Proof sketch: a pairwise property of a list
holds for each of its sublists. -/
theorem Table.KeysUnique.sublist {keys : List UniqueKey} {table other : Table} (unique : table.KeysUnique keys)
    (sublist : other.rows.Sublist table.rows) : other.KeysUnique keys :=
  fun key member => (unique key member).sublist sublist

/-- For every database, position, table and rows: if the database satisfies
{name}`Database.KeysUnique`, it has the table at the position, and the table with the rows
satisfies {name}`Table.KeysUnique` for the unique keys of the position
({name}`Catalog.uniqueKeys`), then the database after {name}`Database.setRows` with the rows at
the position satisfies {name}`Database.KeysUnique`. Proof sketch: the catalog does not change;
at the position the table has the new rows ({name}`Database.table_setRows`), or, for a position
past the end of the row lists, the database does not change; at every other position the table
is the same ({name}`Database.table_setRows_other`). -/
theorem Database.KeysUnique.setRows {database : Database} (unique : database.KeysUnique) {target : Nat} {table : Table}
    (found : database.table target = some table) {rows : List Row}
    (stored : ({ table with rows } : Table).KeysUnique (database.catalog.uniqueKeys target table.shape)) :
    (database.setRows target rows).KeysUnique := by
  intro position other present
  by_cases same : position = target
  · subst same
    by_cases aligned : position < database.rows.length
    · rw [Database.table_setRows rows found aligned, Option.some.injEq] at present
      subst present
      exact stored
    · have unchanged : database.setRows position rows = database := by
        simp only [Database.setRows, List.set_eq_of_length_le (Nat.le_of_not_lt aligned)]
      rw [unchanged] at present ⊢
      exact unique position other present
  · rw [Database.table_setRows_other database rows same] at present
    exact unique position other present

end Belay.Sqlite.Model
