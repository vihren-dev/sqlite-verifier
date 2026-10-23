import Belay.Sqlite.Model.TableFailure
import Belay.Sqlite.Model.KeyCandidates

set_option doc.verso true

/-! The constraints that SQLite may name for a failure, and SQLite 3.51's message for each,
measured with the {lit}`sqlite3` shell. The messages come from the catalog: the names of tables,
columns and indexes as written, the labels of CHECK constraints, and the order of the keys. -/

namespace Belay.Sqlite.Model

/-- One constraint that SQLite may name in its message. For example, a NULL in the NOT NULL
column 1 of the table at catalog position 0 is {lean}`ConstraintFailure.row 0 (.notNull 1)`. -/
inductive ConstraintFailure where
  /-- A failure of the table at the catalog position that is not a unique key. -/
  | row (table : Nat) (failure : TableFailure)
  /-- The unique key at the position in {name}`Catalog.uniqueKeys` of the table at the catalog
  position. -/
  | key (table : Nat) (index : Nat)
  /-- The index of a {lit}`CREATE UNIQUE INDEX` with the name, which the rows of its table fail.
  The index is not in the catalog, because the statement fails. -/
  | uniqueIndex (name : Identifier) (index : CatalogIndex)
  deriving Repr, DecidableEq

/-- The name of the storage class of a value in SQLite's message about a {lit}`STRICT` column;
an integer is {lit}`INT`. {assert}`(Value.integer 1).className = "INT"`. -/
def Value.className : Value → String
  | .null => "NULL" | .integer _ => "INT" | .real _ => "REAL" | .text _ => "TEXT" | .blob _ => "BLOB"

/-- The name of the catalog object at the position as written, empty for no object. -/
def Catalog.objectName (catalog : Catalog) (position : Nat) : String :=
  (catalog[position]?.map (toString ·.name)).getD ""

/-- A column as SQLite names it in a message: the table name, a dot and the column name, both as
written, for example {lit}`invoices.customer`. -/
def Catalog.columnText (catalog : Catalog) (table : Nat) (shape : CatalogTable) (column : Nat) : String :=
  s!"{catalog.objectName table}.{(shape.columns[column]?.map (toString ·.name)).getD ""}"

/-- SQLite's message for a key that fails: {lit}`UNIQUE constraint failed: ` and the columns of
the key in key order ({name}`Catalog.columnText`), separated by {lit}`, `; or, when a term of the
key is an expression, {lit}`index '` with the name of the index and {lit}`'`. -/
def Catalog.keyText (catalog : Catalog) (table : Nat) (shape : CatalogTable) (indexName : String) (key : UniqueKey) :
    String :=
  "UNIQUE constraint failed: " ++
    match key.terms.mapM (fun term => match term.term with | .column position => some position | .expression _ => none) with
    | some positions => ", ".intercalate (positions.map (catalog.columnText table shape))
    | none => s!"index '{indexName}'"

/-- SQLite's message for the constraint, from the catalog:

* NOT NULL: {lit}`NOT NULL constraint failed: t.c`;
* a {lit}`STRICT` type: {lit}`cannot store TEXT value in INT column t.c`;
* CHECK: {lit}`CHECK constraint failed: ` and the label;
* a repeated rowid: {lit}`UNIQUE constraint failed: t.rowid`;
* a key: {name}`Catalog.keyText`.

A table or key that is not in the catalog gives empty names. -/
def ConstraintFailure.message (catalog : Catalog) : ConstraintFailure → String
  | .uniqueIndex name index => catalog.keyText index.table ((catalog.tableAt index.table).getD { columns := [] })
      (toString name) index.uniqueKey
  | .key table position =>
    let shape := (catalog.tableAt table).getD { columns := [] }
    let indexName := match (catalog.keySources table shape)[position]? with
      | some (.index place) => catalog.objectName place
      | some .primaryKey | some (.unique _) | none => ""
    (((catalog.uniqueKeys table shape)[position]?).map (catalog.keyText table shape indexName)).getD
      "UNIQUE constraint failed"
  | .row table failure =>
    let shape := (catalog.tableAt table).getD { columns := [] }
    match failure with
    | .notNull column => s!"NOT NULL constraint failed: {catalog.columnText table shape column}"
    | .strictType column value =>
      let type := ((shape.columns[column]?).bind (·.strictType)).map StrictType.name |>.getD ""
      s!"cannot store {value.className} value in {type} column {catalog.columnText table shape column}"
    | .check label => s!"CHECK constraint failed: {label}"
    | .rowid => s!"UNIQUE constraint failed: {catalog.objectName table}.rowid"
    | .keys _ => "UNIQUE constraint failed"

/-- The constraints that SQLite may name for one failure of the table at the position: for keys,
those of {name}`keyCandidates`; for a repeated rowid, the PRIMARY KEY when the table has a rowid
alias; otherwise the failure itself. -/
def Catalog.keyedCandidates (catalog : Catalog) (table : Nat) : TableFailure → List ConstraintFailure
  | .keys failing =>
    let shape := (catalog.tableAt table).getD { columns := [] }
    (keyCandidates (catalog.keySources table shape) shape failing).map (.key table)
  | .rowid =>
    let shape := (catalog.tableAt table).getD { columns := [] }
    if shape.rowidAlias.isSome && !shape.primaryKey.isEmpty then [.key table 0] else [.row table .rowid]
  | failure@(.notNull _) | failure@(.strictType _ _) | failure@(.check _) => [.row table failure]

/-- The constraints that SQLite may name for one failure of the table at the position
({name}`Catalog.keyedCandidates`), or the failure itself when that list is empty. -/
def Catalog.candidates (catalog : Catalog) (table : Nat) (failure : TableFailure) : List ConstraintFailure :=
  match catalog.keyedCandidates table failure with
  | [] => [.row table failure]
  | found@(_ :: _) => found

/-- For every catalog, table position and failure: {name}`Catalog.candidates` is not empty. Proof
sketch: by cases on the keyed candidates; an empty list gives the one candidate of the row. -/
theorem Catalog.candidates_ne_nil (catalog : Catalog) (table : Nat) (failure : TableFailure) :
    catalog.candidates table failure ≠ [] := by
  unfold Catalog.candidates; split <;> simp

/-- What SQLite's choice among several candidates may depend on, which the model does not keep.
The choice does not always depend on it: SQLite can name the same constraint for every place or
order. -/
inductive CandidateReason where
  /-- The place of the PRIMARY KEY among the UNIQUE constraints in {lit}`CREATE TABLE`. -/
  | primaryKeyPlace
  /-- The order in which an UPDATE visits its rows, which SQLite's query planner chooses. -/
  | rowOrder
  deriving Repr, DecidableEq

/-- The text of the reason in a message. -/
def CandidateReason.text : CandidateReason → String
  | .primaryKeyPlace => "the place of the PRIMARY KEY among the UNIQUE constraints"
  | .rowOrder => "the order in which the UPDATE visits the rows"

/-- The constraints that SQLite may name for a statement that fails, and what the choice may
depend on when there are several. -/
structure ConstraintReport where
  /-- The constraints, one of which SQLite names. -/
  candidates : List ConstraintFailure
  /-- What SQLite's choice may depend on when there are several candidates. -/
  reason : CandidateReason := .primaryKeyPlace
  deriving Repr

/-- The message of a report whose list of candidates is empty. The model gives one for every
plain write that fails with a constraint error ({lit}`failingConstraints_ne_nil`), so this text
names a defect. -/
def noCandidateMessage : String :=
  "constraint failed, and the model names no constraint for it. This is a defect of the model; " ++
    "report the SQL text to the maintainers of the model"

/-- The message of the report: SQLite's message when all candidates give one text, and otherwise
each text and what SQLite's choice depends on. For example, for the two keys of a table
{lit}`u(a, b, UNIQUE(a), PRIMARY KEY(b))` it is {lit}`a constraint failed, and SQLite names one of
these: "UNIQUE constraint failed: u.a" or "UNIQUE constraint failed: u.b". Which one may depend on
the place of the PRIMARY KEY among the UNIQUE constraints, which the model does not keep`. -/
def ConstraintReport.message (catalog : Catalog) (report : ConstraintReport) : String :=
  match (report.candidates.map (·.message catalog)).eraseDups with
  | [] => noCandidateMessage
  | [one] => one
  | several@(_ :: _ :: _) =>
    "a constraint failed, and SQLite names one of these: " ++
      " or ".intercalate (several.map fun text => s!"\"{text}\"") ++
      s!". Which one may depend on {report.reason.text}, which the model does not keep"

end Belay.Sqlite.Model
