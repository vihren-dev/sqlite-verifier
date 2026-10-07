import SqliteVerifier.Model

set_option doc.verso true

/-! A closed literal-DML domain. Admission is a proof obligation, separate from
native constraint failures. Unmodeled coercions/comparisons are never SQL errors. -/
namespace SqliteVerifier
namespace LiteralData

/-- Check SQLite's signed 64-bit range for literals and stored comparison keys.
{assert}`boundedInteger 0 = true`; the upper bound itself is excluded. -/
def boundedInteger (value : Int) : Bool := decide (-(2 ^ 63 : Int) ≤ value ∧ value < 2 ^ 63)

/-- Require no NUL byte and at least one byte outside digits, signs, decimal
points, exponents and ASCII whitespace. This sufficient test prevents numeric
affinity conversion; {assert}`nonnumericText [] = false`. It is not a text decoder. -/
def nonnumericText (bytes : List UInt8) : Bool :=
  !bytes.contains 0 && bytes.any (fun byte =>
    !("0123456789+-.eE \t\r\n\x0b\x0c".toUTF8.toList.contains byte))

/-- Admit values whose modeled affinity conversion keeps them unchanged.
NULL and BLOB pass. Integers must be bounded with INTEGER, NUMERIC or BLOB
affinity. Text passes with TEXT or BLOB affinity, or with INTEGER or NUMERIC
affinity when {name}`nonnumericText` holds. REAL values do not pass.
Use {lean}`Value.null` for NULL; constraint checks remain separate. -/
def lossless (column : Column) : Value → Bool
  | .null | .blob _ => true
  | .integer value => boundedInteger value &&
      [.integer, .numeric, .blob].contains column.affinity
  | .text bytes => [.text, .blob].contains column.affinity ||
      ([.integer, .numeric].contains column.affinity && nonnumericText bytes)
  | .real _ => false

/-- Read the cell at the first column with the given name. Return
{name}`Option.none` for an absent column or missing cell, so malformed rows
cannot supply an invented value. This lookup does not require table validity. -/
def read (table : Table) (row : Row) (name : String) : Option Value := do
  let index ← table.columns.findIdx? (fun column => column.name == name)
  row.values[index]?

/-- Admit NULL or a signed 64-bit integer for exact modeled comparisons.
{assert}`integerOrNull Value.null = true`; every other stored class fails. -/
def integerOrNull : Value → Bool
  | .null => true
  | .integer value => boundedInteger value
  | _ => false

/-- Require a column with the given name and INTEGER, NUMERIC or BLOB affinity.
Also require {name}`read` of that name in every row to yield a value accepted
by {name}`integerOrNull`. With no rows only the column requirement remains.
Use this domain check before integer equality or key comparisons. -/
def comparisonReady (table : Table) (name : String) : Bool :=
  table.columns.any (fun column => column.name == name &&
    [.integer, .numeric, .blob].contains column.affinity) &&
  table.rows.all (fun row => (read table row name).any integerOrNull)

/-- For each key name, require both reads to be integers with equal values.
A missing, NULL or other cell makes the comparison false, as needed for the
admitted ordinary UNIQUE keys. An empty key compares equal vacuously;
{assert}`keyEqual { columns := [], rows := [] } [] { rowid := 0, values := [] }
  { rowid := 1, values := [] } = true`. Key admission is a separate check. -/
def keyEqual (table : Table) (key : List String) (first second : Row) : Bool :=
  key.all fun name => match read table first name, read table second name with
    | some (.integer a), some (.integer b) => a == b
    | _, _ => false

/-- Reject each row that compares equal under {name}`keyEqual` to a later row.
Preserve duplicate NULL-containing keys because those comparisons are false.
Use an empty row list for an empty table: the check then succeeds for any key. -/
def uniqueRows (table : Table) (key : List String) : List Row → Bool
  | [] => true
  | row :: rest => !(rest.any (keyEqual table key row)) && uniqueRows table key rest

/-- Check modeled NOT NULL cells and every retained key's pairwise uniqueness.
NOT NULL checks inspect only zipped column/cell pairs; row width is checked
separately. A table with no rows satisfies both checks. In the admitted domain,
these checks represent ABORT constraints, rather than admission restrictions. -/
def constraints (table : Table) : Bool :=
  table.rows.all (fun row => (table.columns.zip row.values).all
    (fun (column, value) => !column.notNull || value != .null)) &&
  table.properties.keys.all (fun key => uniqueRows table key table.rows)

/-- Require {name}`comparisonReady` for every field of every retained key,
and {name}`constraints` on the old table. With no keys, comparison requirements
are vacuous; constraints still apply. Use this check to admit literal DML. -/
def tableReady (table : Table) : Bool :=
  table.properties.keys.all (fun key => key.all (comparisonReady table)) && constraints table

/-- Return 1 for no rows, otherwise one more than the largest stored rowid,
even when that largest rowid is negative; {assert}`nextRowid [] = 1`.
SQLite's random-search branch at the maximum rowid requires separate admission. -/
def nextRowid (rows : List Row) : Int :=
  match rows with
  | [] => 1
  | first :: rest => (rest.foldl (fun largest row => max largest row.rowid) first.rowid) + 1

/-- Require exactly the table's ordered column names and one value per column.
Require {name}`lossless` on every column/value pair, {name}`tableReady`, a bounded
{name}`nextRowid`, and integer-or-NULL reads for every new key component.
Supplying every value avoids implicit defaults. This admits evaluation;
the inserted table's constraint truth is checked separately. -/
def insertReady (table : Table) (columns : List String) (values : List Value) : Bool :=
  columns == table.columns.map Column.name && values.length == table.columns.length &&
  (table.columns.zip values).all (fun (column, value) => lossless column value) &&
  tableReady table && boundedInteger (nextRowid table.rows) &&
  table.properties.keys.all (fun key => key.all fun name =>
    (read table { rowid := 0, values := values } name).any integerOrNull)

/-- Append one row with {name}`nextRowid` and the supplied cells. Retain columns,
properties and old row order. Callers establish {name}`insertReady` and the
result's constraints separately; this function accepts any supplied value list. -/
def inserted (table : Table) (values : List Value) : Table :=
  { table with rows := table.rows ++ [{ rowid := nextRowid table.rows, values := values }] }

/-- Test whether {name}`read` equals the given tagged integer. NULL, absent
cells and other classes do not match. Use {name}`comparisonReady` to establish
that this exact tagged test represents the admitted SQL equality. -/
def matchesKey (table : Table) (row : Row) (key : String) (value : Int) : Bool :=
  read table row key == some (.integer value)

/-- Set the first matching column in each row accepted by {name}`matchesKey`.
Retain every rowid, other cell and metadata field. An absent target column
leaves the table unchanged; a cell index beyond a row's width changes nothing.
Callers check the admitted assignment domain separately. -/
def updated (table : Table) (column : String) (value : Value) (key : String) (equals : Int) : Table :=
  match table.columns.findIdx? (fun item => item.name == column) with
  | none => table
  | some index => { table with rows := table.rows.map fun row =>
      if (matchesKey table row key equals) then { row with values := row.values.set index value } else row }

/-- Require a bounded comparison integer, {name}`tableReady`, a comparison-ready
key retained as a singleton key, and a target column that accepts the value
under {name}`lossless`. Require every key component to remain comparison-ready
after {name}`updated`. The admitted unique equality key permits at most one
matching row. This check does not establish the updated constraints. -/
def updateReady (table : Table) (column : String) (value : Value) (key : String) (equals : Int) : Bool :=
  boundedInteger equals && tableReady table && comparisonReady table key &&
  table.properties.keys.contains [key] &&
  table.columns.any (fun item => item.name == column && lossless item value) &&
  (updated table column value key equals).properties.keys.all (fun names =>
    names.all (comparisonReady (updated table column value key equals)))

end LiteralData
end SqliteVerifier
