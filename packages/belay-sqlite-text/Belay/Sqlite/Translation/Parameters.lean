import Belay.Sqlite.Translation.Tree

set_option doc.verso true

/-! The numbers of the parameters of one statement (ADR 0019, D1), as
{lit}`sqlite3ExprAssignVarNumber` gives them while SQLite parses the statement, and the errors
that SQLite gives for a parameter token. The translation does not map the expressions of a
statement in text order, so it numbers the {lit}`VARIABLE` tokens of each command first, in the
order of their bytes, and each expression reads its number by the token's first byte. -/

namespace Belay.Sqlite.Translation

open Belay.Sqlite.Model

/-- The {lit}`VARIABLE` tokens under a node, in the order of their bytes. -/
def variableTokens (tree : SqlTree) (node : ParseNode) : Array ParseNode := Id.run do
  let mut found : Array ParseNode := #[]
  let mut pending : Array ParseNode := #[node]
  let mut fuel := tree.nodes.size + 1
  while fuel > 0 do
    fuel := fuel - 1
    let some item := pending.back? | break
    pending := pending.pop
    pending := pending ++ tree.children item
    if item.symbol == "VARIABLE" then found := found.push item
  return found.qsort (·.start < ·.start)

/-- The numbering of a statement so far: the largest number, and each name with its number. -/
structure Numbering where
  /-- The largest number so far, as SQLite's {lit}`nVar`. -/
  largest : Nat := 0
  /-- The names, such as {lit}`:a`, with their numbers. -/
  names : List (String × Nat) := []

/-- The refusal of a parameter token: SQLite's message and what the user can do. -/
def parameterError (token : ParseNode) (message : String) : Refusal :=
  { status := "INPUT_ERROR", start := token.start, stop := token.stop, message }

/-- The number of one parameter token with its text, and the numbering after it, or SQLite's
error: {lit}`?` takes one more than the largest number; {lit}`?NNN` takes NNN, between 1 and the
limit; a name takes the number of its first use, and its first use takes one more than the
largest number; a number above the limit is {lit}`too many SQL variables`. {lit}`#` and a digit
is a syntax error, as SQLite's grammar action gives it. -/
def numberToken (limit : Nat) (numbering : Numbering) (token : ParseNode) (text : String) :
    Except Refusal (Nat × Numbering) := do
  let (number, next) ← match text.toList with
    | ['?'] => pure (numbering.largest + 1, { numbering with largest := numbering.largest + 1 })
    | '?' :: digits =>
      let explicit := (String.ofList digits).toNat!
      if explicit < 1 || explicit > limit then
        throw (parameterError token s!"SQLite refuses the parameter {text}: variable number must be between ?1 and ?{limit}; number the parameters from ?1 to ?{limit}")
      pure (explicit, { numbering with largest := max numbering.largest explicit })
    | '#' :: digit :: _ =>
      if digit.isDigit then
        throw (parameterError token s!"SQLite's grammar rejects the SQL: near \"{text}\": syntax error; write the parameter as ?NNN or a name such as :name")
      named numbering text
    | _ => named numbering text
  if number > limit then
    throw (parameterError token s!"SQLite refuses the parameter {text}: too many SQL variables; use at most {limit} parameter numbers in one statement")
  return (number, next)
where
  /-- The number of a name: the number of its first use, or one more than the largest number. -/
  named (numbering : Numbering) (text : String) : Except Refusal (Nat × Numbering) :=
    match numbering.names.lookup text with
    | some number => pure (number, numbering)
    | none =>
      let number := numbering.largest + 1
      pure (number, { largest := number, names := (text, number) :: numbering.names })

/-- One parameter token of a statement: its text, such as {lit}`:id` or {lit}`?`, the number
that SQLite gives it, and its byte range in the SQL text. The statement syntax holds only the
number ({name}`Syntax.Expr.parameter`), so the surface reads the text and the range here, to
give each parameter a Lean argument or variable and to show an error at the parameter. -/
structure Parameter where
  /-- The text of the token, with its sign, such as {lit}`$x` or {lit}`?5`. -/
  text : String
  /-- The number that SQLite gives the token ({name}`numberToken`). -/
  number : Nat
  /-- The first byte of the token. -/
  start : Nat
  /-- The byte after the token. -/
  stop : Nat
  deriving Inhabited, Repr

/-- The parameter tokens of a command in text order, each with its number, or the refusal of
the first token in text order that SQLite refuses. -/
def numberParameters (limit : Nat) (tree : SqlTree) (command : ParseNode) :
    Except Refusal (List Parameter) := do
  let mut numbering : Numbering := {}
  let mut parameters : Array Parameter := #[]
  for token in variableTokens tree command do
    let text := tree.text token
    let (number, next) ← numberToken limit numbering token text
    numbering := next
    parameters := parameters.push { text, number, start := token.start, stop := token.stop }
  return parameters.toList

/-- A statement with its ranges, and its parameter tokens in text order. -/
structure ParameterizedStatement where
  /-- The statement with the ranges of its parts. -/
  statement : Located Syntax.Statement
  /-- The parameter tokens of the statement, in text order ({name}`numberParameters`). -/
  parameters : List Parameter

end Belay.Sqlite.Translation
