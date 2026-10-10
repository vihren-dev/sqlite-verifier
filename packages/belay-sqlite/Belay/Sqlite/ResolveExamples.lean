import Belay.Sqlite.Resolve

set_option doc.verso true

/-! Examples of {name}`Belay.Sqlite.resolve`, checked by {lit}`#guard` in the compiled
evaluator when the package builds. They check this repository's resolution rules
for each statement, each prepare error, the limits under a lowered profile limit,
the affinity and rowid-alias rules, ASCII-only folding, the shared namespace and
the transactions. The conformance suite compares the same rules with SQLite. -/

namespace Belay.Sqlite.ResolveExamples

open Belay.Sqlite Syntax

/-- SQLite 3.51.0 with its documented default limits. -/
def defaults : Profile := Profile.documented "3.51.0" "2025-11-04 19:38:17 fb2c931ae597f8d00a37574ff67aeed3eced4e5547f9120744ae4bfa8e74527b"

/-- The same release with the column limit lowered to 3, so a constant limit fails. -/
def lowered : Profile := { defaults with limits := { defaults.limits with columns := 3 } }

/-- Resolve statements that the execution semantics runs, from a catalog. -/
def migration (catalog : Catalog) (script : List Syntax.Statement) (profile : Profile := defaults) : ResolveResult :=
  resolve { profile, mode := .execution } catalog script

/-- Resolve a catalog description from the empty catalog. -/
def schema (script : List Syntax.Statement) : ResolveResult :=
  resolve { profile := defaults, mode := .description } [] script

/-- A column definition without constraints. -/
def column (name : String) (declaredType : Option String := some "TEXT") : ColumnDefinition :=
  { name, declaredType, constraints := [] }

/-- The statements of a resolution, or the empty list for a restriction. -/
def statements : ResolveResult → List Resolved.Statement
  | .resolved statements _ => statements
  | .restricted _ => []

/-- The catalog after a resolution, or the empty catalog for a restriction. -/
def catalogOf : ResolveResult → Catalog
  | .resolved _ catalog => catalog
  | .restricted _ => []

/-- Whether the resolution is a model restriction. -/
def restricted : ResolveResult → Bool
  | .restricted _ => true
  | .resolved .. => false

/-- The reason of a model restriction, or the empty text for a resolution. -/
def reason : ResolveResult → String
  | .restricted restriction => restriction.reason
  | .resolved .. => ""

/-- A catalog with table {lit}`t(a TEXT, b INTEGER)`. -/
def tableT : Catalog := catalogOf (migration [] [.createTable "t" [column "a", column "b" (some "INTEGER")] []])

-- Affinity rules in documented order; "CHARINT" and "FLOATING POINT" contain INT.
#guard [some "CHARINT", some "FLOATING POINT", some "VARCHAR(10)", some "DOUBLE", none,
  some "real blob", some "DECIMAL"].map affinityOf == [.integer, .integer, .text, .real, .blob, .blob, .numeric]

-- Rowid alias: INTEGER PRIMARY KEY is an alias (a model restriction); DESC and BIGINT are not.
#guard restricted (schema [.createTable "t" [{ name := "x", declaredType := some "integer", constraints := [.primaryKey false] }] []])
#guard restricted (schema [.createTable "t" [column "x" (some "INTEGER")] [.primaryKey ["x"]]])
#guard (catalogOf (schema [.createTable "t" [{ name := "x", declaredType := some "INTEGER", constraints := [.primaryKey true] }] []])).map (·.entry)
  == [.table { columns := [{ name := "x", declaredType := some "INTEGER" }], primaryKey := [0] }]
#guard !restricted (schema [.createTable "t" [{ name := "x", declaredType := some "BIGINT", constraints := [.primaryKey false] }] []])

-- ASCII-only folding: "Ab" and "aB" are one name; "É" and "é" are two.
#guard statements (migration [] [.createTable "Ab" [column "x"] [], .createTable "aB" [column "x"] []])
  matches [_, .prepareError (.tableExists "aB")]
#guard (catalogOf (migration [] [.createTable "É" [column "x"] [], .createTable "é" [column "x"] []])).length == 2

-- One namespace: a table and an index cannot share a name.
#guard statements (schema [.createTable "t" [column "a"] [], .createIndex "t" false "t" ["a"]])
  matches [_, .prepareError (.tableNameUsed "t")]
#guard statements (schema [.createTable "t" [column "a"] [], .createIndex "i" false "t" ["a"], .createTable "I" [column "a"] []])
  matches [_, _, .prepareError (.indexNameUsed "I")]

-- Column limit from the profile: 3 columns pass, 4 fail; ADD COLUMN to a full table fails.
#guard !(statements (migration [] [.createTable "t" [column "a", column "b", column "c"] []] lowered)
  matches [.prepareError _])
#guard statements (migration [] [.createTable "t" [column "a", column "b", column "c", column "d"] []] lowered)
  == [.prepareError (.tooManyColumns "t")]
#guard statements (migration [] [.createTable "t" [column "a", column "b", column "c"] [], .addColumn "t" (column "d")] lowered)
  matches [_, .prepareError (.tooManyColumns "t")]

-- Two errors in one statement: SQLite reports the first check that fails, column by column.
#guard statements (migration [] [.createTable "t" [column "a", column "A", column "b", column "c"] []] lowered)
  == [.prepareError (.duplicateColumn "A")]
#guard statements (migration [] [.createTable "t" [column "a", column "b", column "c", column "c"] []] lowered)
  == [.prepareError (.tooManyColumns "t")]

-- ADD COLUMN: a missing table, a used name, and the appended column.
#guard statements (migration tableT [.addColumn "u" (column "c"), .addColumn "T" (column "A"), .addColumn "t" (column "c")])
  == [.prepareError (.noSuchTable "u"), .prepareError (.duplicateColumn "A"), .addColumn 0 { name := "c", declaredType := some "TEXT" }]

-- INSERT: errors in SQLite's order, and full rows with defaults and converted literals.
#guard statements (migration tableT [.insert "u" none [[.null]], .insert "t" (some ["z"]) [[.null]],
    .insert "t" none [[.null]], .insert "t" (some ["a"]) [[.null, .null]], .insert "t" none [[.null], [.null, .null]]])
  == [.prepareError (.noSuchTable "u"), .prepareError (.tableHasNoColumn "t" "z"),
      .prepareError (.valueCount "t" 2 1), .prepareError (.valuesForColumns 2 1), .prepareError .valuesDiffer]
#guard statements (migration tableT [.insert "t" (some ["B"]) [[.numeric "1_000"], [.numeric "0x10"], [.negate (.numeric "9223372036854775808")]]])
  == [.insert 0 [[.null, .integer 1000], [.null, .integer 16], [.null, .integer (-9223372036854775808)]]]
#guard restricted (migration tableT [.insert "t" (some ["b"]) [[.numeric "9223372036854775808"]]])
#guard statements (migration tableT [.insert "t" (some ["b"]) [[.numeric "0x10000000000000000"]]])
  == [.prepareError (.hexLiteralTooBig "0x10000000000000000")]

-- Double-quoted strings: a string literal when DQS_DML is on, else "no such column".
#guard statements (migration tableT [.insert "t" (some ["a"]) [[.identifier "x" true]]])
  == [.insert 0 [[.text [120], .null]]]
#guard statements (migration tableT [.insert "t" (some ["a"]) [[.identifier "x" true]]] { defaults with dqsDml := false })
  == [.prepareError (.noSuchColumn "x")]

-- UPDATE: SET and WHERE names, and the modeled integer equality filter.
#guard statements (migration tableT [.update "t" [("z", .null)] none, .update "t" [("a", .null)] (some (.equals (.identifier "z" false) (.numeric "1"))),
    .update "t" [("A", .string [111])] (some (.equals (.identifier "b" false) (.numeric "7")))])
  == [.prepareError (.noSuchColumn "z"), .prepareError (.noSuchColumn "z"), .update 0 [(0, .text [111])] (some (1, .integer 7))]
#guard restricted (migration tableT [.update "t" [("a", .null)] (some (.equals (.identifier "a" false) (.numeric "1")))])

-- Transactions: ROLLBACK restores the catalog of BEGIN; COMMIT keeps the changes.
#guard statements (migration [] [.begin, .createTable "t" [column "a"] [], .rollback, .createTable "t" [column "a"] []])
  matches [.begin, .createTable .., .rollback, .createTable ..]
#guard statements (migration [] [.begin, .createTable "t" [column "a"] [], .commit, .createTable "t" [column "a"] []])
  matches [.begin, .createTable .., .commit, .prepareError (.tableExists "t")]

-- A statement after a prepare error resolves as if that statement had no effect.
#guard statements (migration tableT [.createTable "t" [column "x"] [], .addColumn "t" (column "c")])
  matches [.prepareError (.tableExists "t"), .addColumn 0 _]

-- Statements that run keep the model scope; descriptions may contain the statistics tables.
#guard restricted (migration [] [.createTable "t" [{ name := "a", declaredType := none, constraints := [.notNull] }] []])
#guard restricted (migration tableT [.createIndex "i" false "t" ["a"]])
#guard statements (migration [] [.createTable "sqlite_x" [column "a"] []]) == [.prepareError (.reservedName "sqlite_x")]
#guard !restricted (schema [.createTable "sqlite_stat1" [column "tbl" none, column "idx" none, column "stat" none] []])

-- Restriction messages say what to do next.
#guard reason (schema [.createTable "t" [{ name := "x", declaredType := some "INTEGER", constraints := [.primaryKey false] }] []])
  == "INTEGER PRIMARY KEY rowid aliases are not modeled; declare the key column with another type, such as BIGINT"
#guard reason (migration tableT [.insert "t" (some ["b"]) [[.string [49]]]])
  == "the column affinity would convert this value; write NULL, a blob, or a value that the affinity keeps unchanged"

end Belay.Sqlite.ResolveExamples
