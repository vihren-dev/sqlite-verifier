import SqliteVerifier.Model

/-! A closed literal-DML domain. Admission is a proof obligation, separate from
native constraint failures. Unmodeled coercions/comparisons are never SQL errors. -/
namespace SqliteVerifier
namespace LiteralData

/-- Integer literals and stored comparison keys stay within SQLite's signed range. -/
def boundedInteger (value : Int) : Bool := decide (-(2 ^ 63 : Int) ≤ value ∧ value < 2 ^ 63)

/-- A nonnumeric byte and no NUL suffice to prevent numeric-affinity conversion. -/
def nonnumericText (bytes : List UInt8) : Bool :=
  !bytes.contains 0 && bytes.any (fun byte =>
    !("0123456789+-.eE \t\r\n\x0b\x0c".toUTF8.toList.contains byte))

/-- Only identity affinity conversions are admitted; defaults are not evaluated. -/
def lossless (column : Column) : Value → Bool
  | .null | .blob _ => true
  | .integer value => boundedInteger value &&
      [.integer, .numeric, .blob].contains column.affinity
  | .text bytes => [.text, .blob].contains column.affinity ||
      ([.integer, .numeric].contains column.affinity && nonnumericText bytes)
  | .real _ => false

/-- Exact column reads fail closed on malformed rows or absent columns. -/
def read (table : Table) (row : Row) (name : String) : Option Value := do
  let index ← table.columns.findIdx? (fun column => column.name == name)
  row.values[index]?

/-- Numeric comparison here is exact only for bounded INTEGER and NULL cells. -/
def integerOrNull : Value → Bool
  | .null => true
  | .integer value => boundedInteger value
  | _ => false

/-- Predicate/key columns exclude TEXT affinity and every unmodeled stored class. -/
def comparisonReady (table : Table) (name : String) : Bool :=
  table.columns.any (fun column => column.name == name &&
    [.integer, .numeric, .blob].contains column.affinity) &&
  table.rows.all (fun row => (read table row name).any integerOrNull)

/-- A NULL component makes an ordinary SQLite unique key nonconflicting. -/
def keyEqual (table : Table) (key : List String) (first second : Row) : Bool :=
  key.all fun name => match read table first name, read table second name with
    | some (.integer a), some (.integer b) => a == b
    | _, _ => false

/-- Pairwise checking does not collapse duplicate NULL keys. -/
def uniqueRows (table : Table) (key : List String) : List Row → Bool
  | [] => true
  | row :: rest => !(rest.any (keyEqual table key row)) && uniqueRows table key rest

/-- These are actual ABORT constraints in the admitted ordinary-table subset. -/
def constraints (table : Table) : Bool :=
  table.rows.all (fun row => (table.columns.zip row.values).all
    (fun (column, value) => !column.notNull || value != .null)) &&
  table.properties.keys.all (fun key => uniqueRows table key table.rows)

/-- DML admission includes old constraint validity and exact key-comparison support. -/
def tableReady (table : Table) : Bool :=
  table.properties.keys.all (fun key => key.all (comparisonReady table)) && constraints table

/-- Empty tables allocate 1; otherwise even a negative largest rowid is incremented.
The random-search branch at MAX is outside this initial DML admission domain. -/
def nextRowid (rows : List Row) : Int :=
  match rows with
  | [] => 1
  | first :: rest => (rest.foldl (fun largest row => max largest row.rowid) first.rowid) + 1

/-- Full, ordered INSERT values avoid implicit defaults and column omission. -/
def insertReady (table : Table) (columns : List String) (values : List Value) : Bool :=
  columns == table.columns.map Column.name && values.length == table.columns.length &&
  (table.columns.zip values).all (fun (column, value) => lossless column value) &&
  tableReady table && boundedInteger (nextRowid table.rows) &&
  table.properties.keys.all (fun key => key.all fun name =>
    (read table { rowid := 0, values := values } name).any integerOrNull)

/-- Literal INSERT appends a real, automatically allocated physical row. -/
def inserted (table : Table) (values : List Value) : Table :=
  { table with rows := table.rows ++ [{ rowid := nextRowid table.rows, values := values }] }

/-- SQL equality with an integer does not match NULL. -/
def matchesKey (table : Table) (row : Row) (key : String) (value : Int) : Bool :=
  read table row key == some (.integer value)

/-- A single literal assignment preserves every rowid and every untouched cell. -/
def updated (table : Table) (column : String) (value : Value) (key : String) (equals : Int) : Table :=
  match table.columns.findIdx? (fun item => item.name == column) with
  | none => table
  | some index => { table with rows := table.rows.map fun row =>
      if (matchesKey table row key equals) then { row with values := row.values.set index value } else row }

/-- At most one row can match the admitted unique, non-TEXT equality key. -/
def updateReady (table : Table) (column : String) (value : Value) (key : String) (equals : Int) : Bool :=
  boundedInteger equals && tableReady table && comparisonReady table key &&
  table.properties.keys.contains [key] &&
  table.columns.any (fun item => item.name == column && lossless item value) &&
  (updated table column value key equals).properties.keys.all (fun names =>
    names.all (comparisonReady (updated table column value key equals)))

end LiteralData
end SqliteVerifier
