import Belay.Sqlite.Translation.Sources

set_option doc.verso true

/-! The clauses of one SELECT. The port of {lit}`belay/sqlite/syntax_select.py`: result columns,
the first table and the joins, or none without FROM, and WHERE, GROUP BY, ORDER BY, LIMIT,
OFFSET, HAVING and DISTINCT. A compound SELECT is in {lit}`CompoundSelect.lean`. WITH, a window
clause and NULLS FIRST or LAST are refused. -/

namespace Belay.Sqlite.Translation

open Belay.Sqlite.Model

/-- The ORDER BY terms of a {lit}`sortlist` in text order, with their direction. -/
def orderTerms (mappers : Mappers) (tree : SqlTree) (node : ParseNode) : TranslateM (Array (Located Syntax.OrderTerm)) := do
  let items ← leftList tree node [(3, ["expr", "sortorder", "nulls"]),
    (5, ["sortlist", "COMMA", "expr", "sortorder", "nulls"])]
  items.mapM fun item => do
    let term := fromEnd item 3
    let direction := fromEnd item 2
    absent (last item) "NULLS FIRST or NULLS LAST"
    let descending := tree.symbols direction == ["DESC"]
    let expression ← mappers.expression tree term
    return composite { expression := expression.value, descending } term.start (max term.stop direction.stop)
      #[expression.span, spanOf direction]

/-- An optional part: the located value, or absent at the clause. -/
def optionalAt (located : Option (Located α)) (node : ParseNode) : Located (Option α) :=
  (located.map (·.present)).getD (missing node.start node.stop)

/-- The LIMIT and OFFSET expressions of a {lit}`limit_opt` node. -/
def limitClause (mappers : Mappers) (tree : SqlTree) (limit : ParseNode) :
    TranslateM (Option (Located Syntax.Expr) × Option (Located Syntax.Expr)) := do
  let bounds := tree.children limit
  match tree.symbols limit with
  | [] => return (none, none)
  | ["LIMIT", "expr"] => return (some (← mappers.expression tree bounds[1]!), none)
  | ["LIMIT", "expr", "OFFSET", "expr"] =>
    let first ← mappers.expression tree bounds[1]!
    return (some first, some (← mappers.expression tree bounds[3]!))
  | ["LIMIT", "expr", "COMMA", "expr"] =>
    let first ← mappers.expression tree bounds[1]!
    return (some (← mappers.expression tree bounds[3]!), some first)
  | _ => unsupported limit "Unsupported LIMIT form; write LIMIT n [OFFSET m]"

/-- The ORDER BY, LIMIT and OFFSET of a compound, which the parser puts on its last term: SQLite
gives a subquery there no place in the model's syntax, so the action refuses it. -/
def compoundTail : String :=
  "A subquery in the ORDER BY or LIMIT of a compound SELECT is not modeled; rewrite the clause without it"

/-- The clauses of a {lit}`oneselect` production, mapped in the order of their text, so the
subqueries of their expressions are listed in that order. With {lit}`tail`, the
{lit}`ORDER BY`, {lit}`LIMIT` and {lit}`OFFSET` of the last term of a compound refuse a subquery
({name}`compoundTail`). -/
def oneSelectClauses (mappers : Mappers) (tree : SqlTree) (one : ParseNode) (tail : Bool := false) :
    TranslateM Clauses := do
  let parts ← require tree one ["SELECT", "distinct", "selcollist", "from", "where_opt", "groupby_opt",
    "having_opt", "orderby_opt", "limit_opt"]
  let (distinct, source, whereNode, group, having, order, limit) :=
    (parts[1]!, parts[3]!, parts[4]!, parts[5]!, parts[6]!, parts[7]!, parts[8]!)
  let results ← resultColumns mappers tree parts[2]!
  let (firstTable, joins) ← if source.children.isEmpty then
      pure (missing source.start source.stop, sequence #[] source.start source.stop)
    else do
      let (first, joins) ← fromClause mappers tree (← require tree source ["FROM", "seltablist"])[1]!
      pure (first.present, joins)
  let condition ← if whereNode.children.isEmpty then pure none
    else some <$> mappers.expression tree (tree.children whereNode)[1]!
  let grouping ← if group.children.isEmpty then pure #[] else do
    let items ← leftList tree (tree.children group)[2]! [(1, ["expr"]), (3, ["nexprlist", "COMMA", "expr"])]
    items.mapM fun item => mappers.expression tree (last item)
  let atTail : {β : Type} → TranslateM β → TranslateM β := fun action =>
    if tail then noSubqueries compoundTail action else action
  let ordering ← atTail (if order.children.isEmpty then pure #[] else orderTerms mappers tree (tree.children order)[2]!)
  let (count, offset) ← atTail (limitClause mappers tree limit)
  let havingPart ← if having.children.isEmpty then pure none
    else some <$> mappers.expression tree (tree.children having)[1]!
  return {
    columns := results, source := firstTable, joins, filter := optionalAt condition whereNode,
    groupBy := sequence grouping group.start group.stop, orderBy := sequence ordering order.start order.stop,
    limit := optionalAt count limit, offset := optionalAt offset limit, having := optionalAt havingPart having,
    distinct := leaf (tree.symbols distinct == ["DISTINCT"]) distinct.start distinct.stop,
    compound := missing one.start one.stop }

end Belay.Sqlite.Translation
