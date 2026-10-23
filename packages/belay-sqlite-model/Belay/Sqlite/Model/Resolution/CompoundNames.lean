import Belay.Sqlite.Model.Resolution.CompoundTerms

set_option doc.verso true

/-! The names of the result columns of a compound {lit}`SELECT` that SQLite sorts as
{lit}`SELECT * FROM (compound)` (ADR 0019, D3; {lit}`convertCompoundSelectToSubquery`). The
columns then have the names of the derived table's columns ({lit}`sqlite3ColumnsFromExprList`),
not the names of the left-most term. For example, the column of
{lit}`SELECT a COLLATE NOCASE FROM t EXCEPT SELECT a FROM u ORDER BY 1 COLLATE BINARY` is named
{lit}`a`, and that of the same compound without {lit}`COLLATE BINARY` is named
{lit}`a COLLATE NOCASE`. -/

namespace Belay.Sqlite.Model

/-- The name that SQLite gives a result column without {lit}`AS` of a derived table before it
resolves the names ({lit}`sqlite3ColumnsFromExprList`): under its {lit}`COLLATE` operators, the
name of an identifier as written, or the column name of {lit}`x.c` as written; none for any other
expression, whose name is its text. For example,
{assert}`(Syntax.Expr.collate (.identifier (name! "A") .none) (name! "nocase")).writtenName = some "A"`. -/
def Syntax.Expr.writtenName : Syntax.Expr → Option String
  | .collate operand _ => operand.writtenName
  | .identifier name _ => some name.text
  | .qualified _ column => some column.text
  | .null | .numeric _ | .string _ | .blob _ | .parameter _ | .currentTime _ | .negate _ | .positive _
  | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .callStar _ | .call .. | .arithmetic .. | .cast ..
  | .exists _ | .inQuery .. | .subquery _ | .inList .. | .between .. | .caseOf .. | .concatenate .. | .raise .. => none

/-- The name without a suffix of {lit}`:` and digits, which SQLite removes before it adds a new
suffix: from the end, SQLite skips the digits, but not the first character, and removes the
rest when it stops at {lit}`:`. For example, {assert}`nameStem "a:12" = "a"`,
{assert}`nameStem "a:" = "a"` and {assert}`nameStem "a1" = "a1"`. -/
def nameStem (name : String) : String :=
  let characters := name.toList
  let digits := min (characters.reverse.takeWhile Char.isDigit).length (characters.length - 1)
  let stop := characters.length - 1 - digits
  if characters[stop]? == some ':' then String.ofList (characters.take stop) else name

/-- The first of the {lit}`attempts` candidates that is not in {lit}`taken`, without ASCII
letter case: {lit}`candidate` itself, else its stem ({name}`nameStem`) with the suffix
{lit}`:` and the number of the next attempt, which is {lit}`5 - attempts` with the five
attempts of {lit}`uniqueColumnName`; none when no attempt is left. -/
def uniqueColumnNameAttempt (taken : List String) : Nat → String → Option String
  | 0, _ => none
  | attempts + 1, candidate =>
    if !taken.any (normalizeIdentifier · == normalizeIdentifier candidate) then some candidate
    else uniqueColumnNameAttempt taken attempts s!"{nameStem candidate}:{5 - attempts}"

/-- The name of a column that is unique among the names {lit}`taken`, which SQLite compares
without ASCII letter case: the name itself, else its stem ({name}`nameStem`) with {lit}`:1`,
then with {lit}`:2`, {lit}`:3` and {lit}`:4` ({name}`uniqueColumnNameAttempt`); none when
these names are taken too, as SQLite then adds a random number. -/
def uniqueColumnName (taken : List String) (name : String) : Option String :=
  uniqueColumnNameAttempt taken 5 name

/-- The names of the derived table's columns from the outputs of the left-most term of a
compound: {lit}`names` are the names of the term, the {lit}`AS` alias or the column name of
{lit}`*` and {lit}`x.*`, which stay; an expression without alias has its name as written
({name}`Syntax.Expr.writtenName`), else its text; the names {lit}`true` and {lit}`false` in
any letter case become {lit}`column` with the column number; and each name is made unique
({name}`uniqueColumnName`). None when SQLite would add a random number. -/
def derivedNames (scope : Scope) (results : List Syntax.ResultColumn) (names : List String) : Option (List String) :=
  let written : List (Option String) := results.flatMap fun
    | .star => scope.visible.map fun _ => none
    | .sourceStar source => ((scope.starColumns? source).map (·.map fun _ => none)).getD []
    | .expression value alias text => [some ((alias.map (·.text)).getD (value.writtenName.getD text))]
  let plain := (written.zip names).zipIdx.map fun ((given, name), index) =>
    let named := given.getD name
    if normalizeIdentifier named == "true" || normalizeIdentifier named == "false" then s!"column{index + 1}" else named
  plain.foldl (fun taken name => taken.bind fun earlier => (uniqueColumnName earlier name).map (earlier ++ [·])) (some [])

end Belay.Sqlite.Model
