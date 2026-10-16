import Belay.Sqlite.SqlExecution

set_option doc.verso true

/-! Examples of INSERT with {lit}`ON CONFLICT` clauses (ADR 0012, amendment 4; slice 5c),
checked by {lit}`#guard` and checked against native SQLite 3.51.0: {lit}`DO NOTHING`,
{lit}`DO UPDATE` with {lit}`excluded` and a filter, rows in order, the order of clauses,
a second key after {lit}`DO UPDATE`, NOT NULL before conflict handling, and the rows
that {lit}`RETURNING` reads. -/

namespace Belay.Sqlite.UpsertExamples
open Belay.Sqlite

/-- {lit}`t(k INTEGER UNIQUE, u INTEGER UNIQUE, v NOT NULL)`: two keys and a NOT NULL
column. -/
def shape : CatalogTable :=
  { columns := [{ name := "k", declaredType := some "INTEGER" }, { name := "u", declaredType := some "INTEGER" },
      { name := "v", declaredType := none, notNull := true }],
    uniqueKeys := [[0], [1]] }

/-- The text value of one ASCII letter. -/
def letter (code : UInt8) : Value := .text [code]

/-- The table with the rows {lit}`(1, 1, 'a')` and {lit}`(2, 2, 'b')` at rowids 1 and 2. -/
def table : Table :=
  { shape, rows := [{ rowid := 1, values := [.integer 1, .integer 1, letter 97] },
                    { rowid := 2, values := [.integer 2, .integer 2, letter 98] }] }

/-- The keys of the table, as resolution gives them. -/
def keys : List (List Nat) := [[0], [1]]

/-- {lit}`excluded.v`: the proposed row starts after the three cells of the table's row. -/
def excludedV : Resolved.Expr := .column 5

/-- {lit}`ON CONFLICT(key) DO UPDATE SET v = value`. -/
def setV (key : List Nat) (value : Resolved.Expr) (filter : Option Resolved.Expr := none) : Resolved.ConflictClause :=
  { target := some key, action := .update [(2, value)] filter }

/-- {lit}`ON CONFLICT(k) DO NOTHING`. -/
def nothingOnK : Resolved.ConflictClause := { target := some [0], action := .nothing }

/-- The policy of an INSERT without {lit}`OR` clause into a table without constraint
algorithms: every constraint is ABORT. -/
def aborts : Resolved.ConflictPolicy := { keys := [], notNull := [] }

/-- The values of the rows after an UPSERT, or none for an error. -/
def valuesAfter (clauses : List Resolved.ConflictClause) (rows : List (List Value)) : Option (List (List Value)) :=
  match LiteralData.upsertRun keys aborts clauses table rows with
  | .ok (result, _) => some (result.rows.map (·.values))
  | .error _ => none

/-- The error of an UPSERT, or none. -/
def errorOf (clauses : List Resolved.ConflictClause) (rows : List (List Value)) : Option ExecutionError :=
  match LiteralData.upsertRun keys aborts clauses table rows with
  | .ok _ => none
  | .error (reason, _, _) => some reason

/-- The values of the rows that {lit}`RETURNING` reads, or none for an error. -/
def returned (clauses : List Resolved.ConflictClause) (rows : List (List Value)) : Option (List (List Value)) :=
  match LiteralData.upsertRun keys aborts clauses table rows with
  | .ok (_, written) => some (written.map (·.values))
  | .error _ => none

-- DO NOTHING skips a conflicting row and inserts another one.
#guard valuesAfter [nothingOnK] [[.integer 1, .integer 9, letter 120], [.integer 3, .integer 3, letter 99]] ==
  some [[.integer 1, .integer 1, letter 97], [.integer 2, .integer 2, letter 98], [.integer 3, .integer 3, letter 99]]
-- DO UPDATE reads excluded; a filter that is not true skips the row.
#guard valuesAfter [setV [0] excludedV] [[.integer 1, .integer 9, letter 120]] ==
  some [[.integer 1, .integer 1, letter 120], [.integer 2, .integer 2, letter 98]]
#guard valuesAfter [setV [0] excludedV (some (.literal .null))] [[.integer 1, .integer 9, letter 120]] ==
  some [[.integer 1, .integer 1, letter 97], [.integer 2, .integer 2, letter 98]]
-- A later row sees the row that an earlier one inserted.
#guard valuesAfter [setV [0] excludedV] [[.integer 5, .integer 5, letter 120], [.integer 5, .integer 6, letter 121]] ==
  some [[.integer 1, .integer 1, letter 97], [.integer 2, .integer 2, letter 98], [.integer 5, .integer 5, letter 121]]
-- The first clause whose target conflicts handles the row; an untargeted key is not checked.
#guard valuesAfter [setV [1] (.literal (letter 117)), setV [0] (.literal (letter 107))]
    [[.integer 1, .integer 2, letter 110]] ==
  some [[.integer 1, .integer 1, letter 97], [.integer 2, .integer 2, letter 117]]
#guard valuesAfter [nothingOnK] [[.integer 1, .integer 2, letter 110]] == some (table.rows.map (·.values))
-- Without a handling clause, a conflict on another key is the ABORT error.
#guard errorOf [nothingOnK] [[.integer 9, .integer 2, letter 110]] == some .constraintViolation
-- The row of DO UPDATE is checked against every key.
#guard errorOf [{ target := some [0], action := .update [(1, .literal (.integer 2))] none }]
    [[.integer 1, .integer 9, letter 120]] == some .constraintViolation
-- NOT NULL fails before conflict handling.
#guard errorOf [nothingOnK] [[.integer 1, .integer 9, .null]] == some .constraintViolation
-- RETURNING reads the inserted and the updated rows, not the skipped ones.
#guard returned [setV [0] excludedV (some (.compare .ne (.column 0) (.literal (.integer 2))))]
    [[.integer 1, .integer 9, letter 120], [.integer 2, .integer 9, letter 121], [.integer 7, .integer 7, letter 122]] ==
  some [[.integer 1, .integer 1, letter 120], [.integer 7, .integer 7, letter 122]]

end Belay.Sqlite.UpsertExamples
