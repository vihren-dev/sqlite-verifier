import Belay.Sqlite.Model.Resolution.CollationExamples

set_option doc.verso true

/-! Examples of the resolution of a compound {lit}`SELECT` (ADR 0019, D3), from the syntax that
the frontend writes: the names and the column count of outcome 4 of the task file, the order of
the prepare errors of outcome 5, the {lit}`ORDER BY` of outcome 7 with its {lit}`COLLATE`
exception, and the affinity and collation that {lit}`IN` and a scalar subquery read from a
compound (outcome 9). Native SQLite 3.51.0 gives the same values; the authored compound corpus
compares them with it. -/

namespace Belay.Sqlite.Model.Resolution.CompoundResolutionExamples

open Belay.Sqlite.Model Syntax Resolution.Examples Resolution.CollationExamples

/-- {lit}`t(a TEXT, n TEXT COLLATE NOCASE)`, {lit}`u(b INTEGER, m TEXT)` and
{lit}`w(n TEXT COLLATE NOCASE)`. -/
def tables : Catalog :=
  catalogOf (schema [.createTable (name! "t") [column (name! "a"), collated (name! "n") (name! "NOCASE")] [],
    .createTable (name! "u") [column (name! "b") (some "INTEGER"), column (name! "m")] [],
    .createTable (name! "w") [collated (name! "n") (name! "NOCASE")] []])

/-- The rows {lit}`('1', 'a')` into {lit}`t`, {lit}`(1, 'A')` into {lit}`u`, and {lit}`'C'` and
{lit}`'a'` into {lit}`w`. -/
def filled : List Syntax.Statement :=
  [insertText (name! "t") [[49], [97]], insertText (name! "u") [[49], [65]], insertText (name! "w") [[67]],
   insertText (name! "w") [[97]]]

/-- A term {lit}`SELECT columns [FROM table] [WHERE filter]` inside the query {lit}`parent`. -/
def term (columns : List ResultColumn) (table : Option String := none) (parent : Option Nat := none)
    (filter : Option Expr := none) : Subquery :=
  { columns, source := table.map fun text => { table := Identifier.ofString text, alias := none }, joins := [], filter,
    groupBy := [], orderBy := [], limit := none, offset := none, parent }

/-- The compound of the terms at the indexes {lit}`first` to {lit}`first + n`, with the
operators between them. -/
def chain (first : Nat) (operators : List CompoundOperator) : Compound :=
  { first, rest := operators.zipIdx.map fun (operator, index) => (operator, first + index + 1) }

/-- A compound statement over its terms, which are the first subqueries, then the other
subqueries. -/
def compound (operators : List CompoundOperator) (terms : List Subquery) (orderBy : List OrderTerm := [])
    (others : List Subquery := []) : Syntax.Statement :=
  .select [] none [] none [] orderBy none none (terms ++ others) none false (some (chain 0 operators))

/-- A compound subquery of the statement's query, at index 0, over the terms after it. -/
def compoundSubquery (operators : List CompoundOperator) (orderBy : List OrderTerm := []) : Subquery :=
  { term [] with orderBy, compound := some (chain 1 operators) }

/-- A result column with an alias. -/
def named (value : Expr) (alias : String) : ResultColumn := .expression value (some (Identifier.ofString alias)) alias

/-- An ascending {lit}`ORDER BY` term. -/
def ascending (value : Expr) : OrderTerm := { expression := value, descending := false }

/-- The integer literal of a text. -/
def num (text : String) : Expr := .numeric text

/-- The single statement of a resolution from {name}`tables`. -/
def resolvedOne (statement : Syntax.Statement) : Option Resolved.Statement :=
  (statements (migration tables [statement])).head?

/-- The prepare error of a statement, if it is one. -/
def errorOf (statement : Syntax.Statement) : Option PrepareError :=
  match resolvedOne statement with
  | some (.prepareError error) => some error
  | some (.createTable ..) | some (.createIndex ..) | some (.createTrigger ..) | some (.addColumn ..) | some (.drop ..)
  | some (.setting _) | some .begin | some .commit | some .rollback | some (.insert ..) | some (.upsert ..)
  | some (.update ..) | some (.delete ..) | some (.query ..) | none => none

/-- The result names of a resolved query statement. -/
def namesOf (statement : Syntax.Statement) : Option (List String) :=
  match resolvedOne statement with
  | some (.query query _) => some query.names
  | some (.createTable ..) | some (.createIndex ..) | some (.createTrigger ..) | some (.addColumn ..) | some (.drop ..)
  | some (.setting _) | some .begin | some .commit | some .rollback | some (.insert ..) | some (.upsert ..)
  | some (.update ..) | some (.delete ..) | some (.prepareError _) | none => none

/-- The rows of a query statement over {name}`filled`, from {name}`tables`. -/
def rowsOf (statement : Syntax.Statement) : Option (List (List Value)) :=
  match migration tables (filled ++ [statement]) with
  | .resolved resolved _ =>
    match resolved.getLast?, runSql (bindValues resolved.dropLast []) tables.emptyDatabase with
    | some (.query query subqueries), .success database => (query.runOn 0 [] database subqueries).map (·.2.rows)
    | some (.query ..), .failure .. | some (.query ..), .pending .. => none
    | some (.createTable ..), _ | some (.createIndex ..), _ | some (.createTrigger ..), _ | some (.addColumn ..), _
    | some (.drop ..), _ | some (.setting _), _ | some .begin, _ | some .commit, _ | some .rollback, _
    | some (.insert ..), _ | some (.upsert ..), _ | some (.update ..), _ | some (.delete ..), _
    | some (.prepareError _), _ | none, _ => none
  | .restricted _ => none

-- Outcome 4: SELECT 1 AS one UNION SELECT 2 AS two names its column one.
example : namesOf (compound [.union] [term [named (num "1") "one"], term [named (num "2") "two"]]) = some ["one"] := by
  decide +kernel
-- SELECT 1 UNION ALL SELECT 1, 2 is the count error with the operator between the terms.
example : errorOf (compound [.unionAll] [term [shown (num "1")], term [shown (num "1"), shown (num "2")]]) =
    some (.expression (.compoundColumns .unionAll)) := by decide +kernel

-- Outcome 5: SQLite finds the tables of the terms from right to left before any name.
example : errorOf (compound [.union] [term [shown (num "1")] "missing1", term [shown (ref (name! "nosuch"))] "missing2"]) =
    some (.noSuchTable (name! "missing2")) := by decide +kernel
example : errorOf (compound [.union] [term [shown (num "1")] "missing", term [shown (ref (name! "nosuch"))] "t"]) =
    some (.noSuchTable (name! "missing")) := by decide +kernel
-- Then it resolves the names of the terms from right to left: nosuch2 first.
example : errorOf (compound [.union] [term [shown (ref (name! "nosuch1"))], term [shown (ref (name! "nosuch2"))]]) =
    some (.expression (.noSuchColumn (name! "nosuch2"))) := by decide +kernel
-- The count of a term and the term on its right after the names of that term.
example : errorOf (compound [.union] [term [shown (ref (name! "nosuch1"))], term [shown (num "1"), shown (num "2")]]) =
    some (.expression (.noSuchColumn (name! "nosuch1"))) := by decide +kernel
example : errorOf (compound [.union, .union]
    [term [shown (ref (name! "nosuch"))], term [shown (num "1")], term [shown (num "1"), shown (num "2")]]) =
    some (.expression (.compoundColumns .union)) := by decide +kernel
-- The ORDER BY comes last: SELECT 1 UNION SELECT 1, 2 ORDER BY 5 is the count error.
example : errorOf (compound [.union] [term [shown (num "1")], term [shown (num "1"), shown (num "2")]] [ascending (num "5")]) =
    some (.expression (.compoundColumns .union)) := by decide +kernel

-- Outcome 7: a column number out of range, and a term that names no column.
example : errorOf (compound [.union] [term [shown (num "1")], term [shown (num "2")]] [ascending (num "2")]) =
    some (.expression (.orderByOutOfRange 1 1)) := by decide +kernel
example : errorOf (compound [.union] [term [shown (num "1")], term [shown (num "2")]] [ascending (num "2147483648")]) =
    some (.expression (.orderByNoMatch 1)) := by decide +kernel
example : errorOf (compound [.union] [term [shown (ref (name! "a"))] "t", term [shown (ref (name! "a"))] "t"]
    [ascending (.arithmetic .add (ref (name! "a")) (num "1"))]) = some (.expression (.orderByNoMatch 1)) := by decide +kernel
-- An alias of a later term, and an expression of a later term, name a column.
example : rowsOf (compound [.union] [term [named (num "2") "a"], term [named (num "1") "b"]] [ascending (ref (name! "b"))]) =
    some [[.integer 1], [.integer 2]] := by decide +kernel
example : rowsOf (compound [.union] [term [shown (ref (name! "a"))] "t", term [shown (.call "lower" [ref (name! "a")])] "t"]
    [ascending (.call "lower" [ref (name! "a")])]) = some [[.text [49]]] := by decide +kernel
-- An aggregate in the ORDER BY of a compound is a restriction.
example : reason (migration tables [compound [.union] [term [shown (ref (name! "a"))] "t", term [shown (num "1")]]
    [ascending (.call "max" [ref (name! "a")])]]) = RestrictionKind.compoundOrderByTerm.message := by decide +kernel

-- The COLLATE exception, over w with 'C' and 'a': SELECT 'b' AS x, 1 AS y UNION SELECT n, 1 FROM w
-- ORDER BY y COLLATE BINARY, x sorts x under BINARY, the collation of the left-most term.
/-- The compound of outcome 7's exception with an operator and an {lit}`ORDER BY`. -/
def exception (operator : CompoundOperator) (orderBy : List OrderTerm) : Syntax.Statement :=
  compound [operator] [term [named (.string [98]) "x", named (num "1") "y"],
    term [shown (ref (name! "n")), shown (num "1")] "w"] orderBy

example : (rowsOf (exception .union [ascending (.collate (ref (name! "y")) (name! "BINARY")), ascending (ref (name! "x"))])).map
    (·.map (·.head?)) = some [some (.text [67]), some (.text [97]), some (.text [98])] := by decide +kernel
example : (rowsOf (exception .union [ascending (ref (name! "y")), ascending (ref (name! "x"))])).map
    (·.map (·.head?)) = some [some (.text [97]), some (.text [98]), some (.text [67])] := by decide +kernel
example : (rowsOf (exception .unionAll [ascending (.collate (ref (name! "y")) (name! "BINARY")), ascending (ref (name! "x"))])).map
    (·.map (·.head?)) = some [some (.text [97]), some (.text [98]), some (.text [67])] := by decide +kernel

/-- {lit}`SELECT a COLLATE NOCASE ..., then the columns, FROM t EXCEPT SELECT a ... FROM t`
with the {lit}`ORDER BY`; the first column has its text as written. -/
def renamed (columns : List ResultColumn) (orderBy : List OrderTerm) : Syntax.Statement :=
  compound [.except] [term (.expression (.collate (ref (name! "a")) (name! "NOCASE")) none "a COLLATE NOCASE" :: columns) "t",
    term (shown (ref (name! "a")) :: columns.map fun _ => shown (num "1")) "t"] orderBy

-- After the COLLATE rewrite, the columns have the names of the derived table's columns.
example : namesOf (renamed [] [ascending (.collate (num "1") (name! "BINARY"))]) = some ["a"] := by decide +kernel
example : namesOf (renamed [] [ascending (num "1")]) = some ["a COLLATE NOCASE"] := by decide +kernel
example : namesOf (renamed [.expression (.qualified (name! "t") (name! "a")) none "t.a", named (num "2") "TRUE"]
    [ascending (.collate (num "1") (name! "BINARY"))]) = some ["a", "a:1", "column3"] := by decide +kernel
-- SQLite names them before it resolves them: likely(a) keeps its text, and A its spelling.
example : namesOf (renamed [.expression (.call "likely" [ref (name! "a")]) none "likely(a)", .expression (ref (name! "A")) none "A"]
    [ascending (.collate (num "1") (name! "BINARY"))]) = some ["a", "likely(a)", "A:1"] := by decide +kernel
-- Five columns of one name end with a:4; with six, SQLite names the sixth at random, which is a restriction.
example : namesOf (renamed (List.replicate 4 (shown (ref (name! "a")))) [ascending (.collate (num "1") (name! "BINARY"))]) =
    some ["a", "a:1", "a:2", "a:3", "a:4"] := by decide +kernel
example : reason (migration tables [renamed (List.replicate 5 (shown (ref (name! "a"))))
    [ascending (.collate (num "1") (name! "BINARY"))]]) = RestrictionKind.compoundOrderByTerm.message := by decide +kernel

/-- {lit}`SELECT value IN (compound)` over the terms. -/
def inCompound (value : Expr) (operators : List CompoundOperator) (terms : List Subquery)
    (orderBy : List OrderTerm := []) : Syntax.Statement :=
  .select [shown (.inQuery value 0 false)] none [] none [] [] none none (compoundSubquery operators orderBy :: terms)

-- Outcome 9: IN reads the affinity and the collation of the right-most term's column.
example : rowsOf (inCompound (.string [49]) [.union] [term [shown (ref (name! "b"))] "u" (some 0), term [shown (num "5")] none (some 0)]) =
    some [[.integer 0]] := by decide +kernel
example : rowsOf (inCompound (.string [49]) [.union] [term [shown (num "5")] none (some 0), term [shown (ref (name! "b"))] "u" (some 0)]) =
    some [[.integer 1]] := by decide +kernel
example : rowsOf (inCompound (.string [65]) [.union]
    [term [shown (ref (name! "n"))] "t" (some 0), term [shown (ref (name! "m"))] "u" (some 0) (some (num "0"))]) =
    some [[.integer 0]] := by decide +kernel
example : rowsOf (inCompound (.string [65]) [.union]
    [term [shown (ref (name! "m"))] "u" (some 0) (some (num "0")), term [shown (ref (name! "n"))] "t" (some 0)]) =
    some [[.integer 1]] := by decide +kernel
-- After the COLLATE rewrite, IN over the compound is a restriction; EXISTS takes it.
example : reason (migration tables [inCompound (.string [65]) [.union]
    [term [shown (.collate (.string [97]) (name! "NOCASE"))] none (some 0), term [shown (.string [98])] none (some 0)]
    [ascending (.collate (num "1") (name! "BINARY"))]]) = RestrictionKind.compoundSubqueryColumn.message := by decide +kernel
example : rowsOf (.select [shown (.exists 0)] none [] none [] [] none none
    [compoundSubquery [.union] [ascending (.collate (num "1") (name! "BINARY"))],
     term [shown (.string [97])] none (some 0), term [shown (.string [98])] none (some 0)]) =
    some [[.integer 1]] := by decide +kernel

end Belay.Sqlite.Model.Resolution.CompoundResolutionExamples
