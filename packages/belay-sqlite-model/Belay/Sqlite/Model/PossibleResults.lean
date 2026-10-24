import Belay.Sqlite.Model.Execution

set_option doc.verso true

/-! The results that SQLite may give for a query (ADR 0018, D6). SQLite promises the order of
{lit}`ORDER BY` only: rows that its terms do not separate, and every row of a query without
{lit}`ORDER BY`, may come in any order. So the model gives each result in a normal form, the rows of
each tie group sorted by {lit}`compareNormal`, and gives every result
that a window cuts out of the groups: a group that {lit}`LIMIT` or {lit}`OFFSET` cuts may give any of its
rows that the window takes. {lit}`PossibleResultsLaws.lean` relates the list to the one result
of {lit}`Query.results`. -/

namespace Belay.Sqlite.Model.Resolved

/-- A total order of values: {name}`Value.compare`, and among the values that it says are equal
but differ, NULL first, an integer before a real, and reals by their bits, so that a NaN REAL,
which the model never makes, is not equal to NULL either. For example, the integer 1 comes
before the real 1.0. -/
def compareNormal (first second : Value) : Ordering :=
  (Value.compare first second).then (match first, second with
    | .integer _, .real _ => .lt
    | .real _, .integer _ => .gt
    | .real a, .real b => compare a b
    | .null, .integer _ | .null, .real _ | .null, .text _ | .null, .blob _ => .lt
    | .integer _, .null | .real _, .null | .text _, .null | .blob _, .null => .gt
    | .null, .null | .integer _, .integer _ | .integer _, .text _ | .integer _, .blob _
    | .real _, .text _ | .real _, .blob _
    | .text _, .integer _ | .text _, .real _ | .text _, .text _ | .text _, .blob _
    | .blob _, .integer _ | .blob _, .real _ | .blob _, .text _ | .blob _, .blob _ => .eq)

/-- The order of two rows: column by column by {name}`compareNormal`, a shorter row first when
one is a prefix of the other. -/
def compareRows : List Value → List Value → Ordering
  | [], [] => .eq
  | [], _ :: _ => .lt
  | _ :: _, [] => .gt
  | first :: rest, other :: others => (compareNormal first other).then (compareRows rest others)

/-- The normal form of rows whose order SQLite does not promise: sorted by {name}`compareRows`. -/
def normalForm (rows : List (List Value)) : List (List Value) :=
  stableSort (fun a b => (compareRows a b).isLE) rows

/-- The tie groups of records in the order of the {lit}`ORDER BY` terms with the directions: the
longest runs of adjacent records that the terms do not separate ({name}`compareSort`). -/
def tieGroups (directions : List (Bool × Collation)) : List Record → List (List Record)
  | [] => []
  | record :: rest => match tieGroups directions rest with
    | (first :: group) :: groups =>
      if compareSort directions record.2 first.2 == .eq then (record :: first :: group) :: groups
      else [record] :: (first :: group) :: groups
    | [] :: groups => [record] :: groups
    | [] => [[record]]

/-- The ways to choose a number of items of a list, each in list order, the first items first. -/
def choose : Nat → List α → List (List α)
  | 0, _ => [[]]
  | _ + 1, [] => []
  | count + 1, item :: rest => (choose count rest).map (item :: ·) ++ choose (count + 1) rest

/-- The lists without their repetitions, each at its first place. -/
def distinctLists [BEq α] : List α → List α
  | [] => []
  | item :: rest => item :: (distinctLists rest).filter (· != item)

/-- The items of a list that a window from index {lit}`start` to index {lit}`stop` takes: those
from {lit}`start`, and before {lit}`stop` when the window has an end. -/
def windowRows (start : Nat) (stop : Option Nat) (items : List α) : List α :=
  match stop with
  | none => items.drop start
  | some stop => (items.drop start).take (stop - start)

/-- The rows of a group at a position in the sorted rows that the window from {lit}`start` to
{lit}`stop` takes, in record order: the window over the group, moved by its position. -/
def groupSlice (start : Nat) (stop : Option Nat) (position : Nat) (group : List (List Value)) : List (List Value) :=
  windowRows (start - position) (stop.map (· - position)) group

/-- The rows that a group at a position may give to the window, each in normal form: all its
rows when the window takes them all, else each choice of as many of its rows as the window
takes ({name}`groupSlice`), none when it takes none. -/
def groupChoices (start : Nat) (stop : Option Nat) (position : Nat) (group : List (List Value)) :
    List (List (List Value)) :=
  if (groupSlice start stop position group).length == group.length then [normalForm group]
  else distinctLists ((choose (groupSlice start stop position group).length group).map normalForm)

/-- The choices of each group in order, from the position of the first. -/
def windowChoices (start : Nat) (stop : Option Nat) : Nat → List (List (List Value)) → List (List (List (List Value)))
  | _, [] => []
  | position, group :: groups =>
    groupChoices start stop position group :: windowChoices start stop (position + group.length) groups

/-- The rows that the window takes of each group in order, in record order
({name}`groupSlice`), from the position of the first. -/
def windowSlices (start : Nat) (stop : Option Nat) : Nat → List (List (List Value)) → List (List (List Value))
  | _, [] => []
  | position, group :: groups => groupSlice start stop position group :: windowSlices start stop (position + group.length) groups

/-- The results of one choice of each group, in order: the rows of the choices, group by group. -/
def choiceResults : List (List (List (List Value))) → List (List (List Value))
  | [] => [[]]
  | choices :: rest => choices.flatMap fun chosen => (choiceResults rest).map (chosen ++ ·)

/-- The window's end of a query: its {lit}`OFFSET` and {lit}`LIMIT` together, none without
{lit}`LIMIT`. -/
def Query.stop (query : Query) : Option Nat := query.limit.map (query.offset + ·)

/-- The records of a query in the stable order of its {lit}`ORDER BY` terms, as
{name}`Query.results` sorts them. -/
def Query.sortedRecords (context : EvalContext) (query : Query) (rows : List (List Value)) : List Record :=
  stableSort (fun a b => (compareSort (query.orderBy.map fun term => (term.descending, term.collation)) a.2 b.2).isLE)
    (query.uniqueRecords context rows)

/-- The result rows of the tie groups of a query's sorted records ({name}`tieGroups`). -/
def Query.tieGroupRows (context : EvalContext) (query : Query) (rows : List (List Value)) : List (List (List Value)) :=
  (tieGroups (query.orderBy.map fun term => (term.descending, term.collation)) (query.sortedRecords context rows)).map
    (·.map Prod.fst)

/-- The one result of {name}`Query.results` with the rows of each tie group in normal form: the
rows that the window takes of each group ({name}`windowSlices`), each in normal form. -/
def Query.normalResult (context : EvalContext) (query : Query) (rows : List (List Value)) : List (List Value) :=
  ((windowSlices query.offset query.stop 0 (query.tieGroupRows context rows)).map normalForm).flatten

/-- Every result that SQLite may give for the query over its source rows, each once: the
records ({name}`Query.uniqueRecords`) in the stable order of the {lit}`ORDER BY` terms, their tie
groups ({name}`tieGroups`), and the rows that the window of {lit}`OFFSET` and {lit}`LIMIT` takes of each
group ({name}`groupChoices`). A query without {lit}`ORDER BY` has one group of all its records. -/
def Query.possibleResults (context : EvalContext) (query : Query) (rows : List (List Value)) :
    List (List (List Value)) :=
  distinctLists (choiceResults (windowChoices query.offset query.stop 0 (query.tieGroupRows context rows)))

end Belay.Sqlite.Model.Resolved

namespace Belay.Sqlite.Model

/-- Every result that SQLite may give for a statement's query over a database at a clock value
with the counters and the values bound to the statement's parameters ({name}`Resolved.Query.possibleResults`),
in the context of its subqueries, as
{name}`Resolved.Query.runOn` gives its one result, with its window bound to the values
({name}`Resolved.Query.bindWindow`); none when a table is missing or a value of the window is not
an integer. -/
def Resolved.Query.possibleOn (query : Resolved.Query) (clock : Int) (counters : Counters) (parameters : List Value) (database : Database)
    (subqueries : List Resolved.Query) : Option (List (List (List Value))) :=
  let context := Resolved.statementContext clock counters parameters database subqueries
  (query.source context database).bind fun source =>
    (query.bindWindow parameters).map fun bound => bound.possibleResults context source.rows

end Belay.Sqlite.Model
