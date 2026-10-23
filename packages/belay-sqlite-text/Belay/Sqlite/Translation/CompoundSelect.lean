import Belay.Sqlite.Translation.Select

set_option doc.verso true

/-! A {lit}`select` production as one SELECT or as a compound SELECT (ADR 0019, D3). The terms of
a compound are subqueries of the statement whose parent is the compound's query, in the order
of their text, so a term comes after the query that holds it and before its own subqueries. The
compound's own clauses are its {lit}`ORDER BY`, {lit}`LIMIT` and {lit}`OFFSET`, which the parser
puts on the last term. The errors of SQLite's parser actions are refused with
{lit}`INPUT_ERROR` and SQLite's message. -/

namespace Belay.Sqlite.Translation

open Belay.Sqlite.Model

/-- The operator of a {lit}`multiselect_op` node. -/
def compoundOperatorOf (tree : SqlTree) (node : ParseNode) : TranslateM CompoundOperator :=
  match tree.symbols node with
  | ["UNION"] => pure .union
  | ["UNION", "ALL"] => pure .unionAll
  | ["EXCEPT"] => pure .except
  | ["INTERSECT"] => pure .intersect
  | _ => unsupportedForm node

/-- The terms of a {lit}`selectnowith` node in text order, and the operator before each term
after the first. -/
def compoundParts (tree : SqlTree) (node : ParseNode) : TranslateM (Array ParseNode × Array CompoundOperator) := do
  let mut terms : Array ParseNode := #[]
  let mut operators : Array CompoundOperator := #[]
  let mut current := node
  let mut fuel := tree.nodes.size + 1
  while tree.symbols current == ["selectnowith", "multiselect_op", "oneselect"] && fuel > 0 do
    fuel := fuel - 1
    let parts := tree.children current
    terms := terms.push parts[2]!
    operators := operators.push (← compoundOperatorOf tree parts[1]!)
    current := parts[0]!
  terms := terms.push (← require tree current ["oneselect"])[0]!
  return (terms.reverse, operators.reverse)

/-- The part of a {lit}`oneselect` node with the symbol, if it is present. -/
def presentClause (tree : SqlTree) (term : ParseNode) (symbol : String) : Option ParseNode :=
  (tree.children term).find? fun part => part.symbol == symbol && !part.children.isEmpty

/-- The error of SQLite's parser action for a compound ({lit}`parserDoubleLinkSelect`), or none.
From the right, the first term before the last with an {lit}`ORDER BY` or a {lit}`LIMIT` is
{lit}`%s clause should come after %s not before`, with the operator on its right; the walk
stops there. When the walk counted more terms than the limit, the message is
{lit}`too many terms in compound SELECT` instead, as the second message replaces the first. -/
def compoundParseError (tree : SqlTree) (node : ParseNode) (terms : Array ParseNode)
    (operators : Array CompoundOperator) (limit : Nat) : Option Refusal :=
  let early := (List.range (terms.size - 1)).reverse.findSome? fun position =>
    let term := terms[position]!
    match presentClause tree term "orderby_opt", presentClause tree term "limit_opt" with
    | some clause, _ => some (position, clause, "ORDER BY")
    | none, some clause => some (position, clause, "LIMIT")
    | none, none => none
  let counted := match early with
    | some (position, _, _) => terms.size - position
    | none => terms.size
  if counted > limit then
    some { status := "INPUT_ERROR", start := node.start, stop := node.stop,
           message := s!"SQLite refuses the compound SELECT: too many terms in compound SELECT; use at most {limit} SELECT terms in one compound" }
  else early.map fun (position, clause, keyword) =>
    { status := "INPUT_ERROR", start := clause.start, stop := clause.stop,
      message := s!"SQLite refuses the compound SELECT: {keyword} clause should come after " ++
        s!"{(operators[position]?.getD .union).keywords} not before; move {keyword} after the last SELECT of the compound" }

/-- The clauses of a compound query from its terms: no columns, sources or other clauses of its
own, the {lit}`ORDER BY`, {lit}`LIMIT` and {lit}`OFFSET` of the last term, and the terms by
their indexes. -/
def compoundClauses (node : ParseNode) (tail : Clauses) (indexes : Array Nat) (operators : Array CompoundOperator) :
    Clauses :=
  let compound : Syntax.Compound := { first := indexes[0]!, rest := operators.toList.zip (indexes.toList.drop 1) }
  { columns := sequence #[] node.start node.stop, source := missing node.start node.stop,
    joins := sequence #[] node.start node.stop, filter := missing node.start node.stop,
    groupBy := sequence #[] node.start node.stop, orderBy := tail.orderBy, limit := tail.limit, offset := tail.offset,
    having := missing node.start node.stop, distinct := leaf false node.start node.stop,
    compound := leaf (some compound) node.start node.stop }

/-- The clauses of a {lit}`select` production: those of one SELECT ({name}`oneSelectClauses`), or
of a compound ({name}`compoundClauses`), whose terms go into the statement's list in text order
({name}`liftWith`), the last without its {lit}`ORDER BY` and {lit}`LIMIT`. A compound with an
error of SQLite's parser ({name}`compoundParseError`) is refused before its terms. -/
def queryClausesWith (mappers : Mappers) (tree : SqlTree) (selectNode : ParseNode) : TranslateM Clauses := do
  let current := (← require tree selectNode ["selectnowith"])[0]!
  let (terms, operators) ← compoundParts tree current
  let some last := terms.back? | unsupportedForm current
  if terms.size == 1 then return ← oneSelectClauses mappers tree last
  if let some refusal := compoundParseError tree current terms operators Limits.documentedDefaults.compoundSelect then
    throw refusal
  let mut tail : Clauses := default
  let mut indexes : Array Nat := #[]
  for position in List.range terms.size do
    let term := terms[position]!
    let isLast := position + 1 == terms.size
    let (index, clauses) ← liftWith term do
      let clauses ← oneSelectClauses mappers tree term isLast
      if !isLast then return (clauses, clauses)
      return ({ clauses with orderBy := sequence #[] clauses.orderBy.span.start clauses.orderBy.span.stop,
                             limit := missing clauses.limit.span.start clauses.limit.span.stop,
                             offset := missing clauses.offset.span.start clauses.offset.span.stop }, clauses)
    tail := clauses
    indexes := indexes.push index
  return compoundClauses current tail indexes operators

end Belay.Sqlite.Translation
