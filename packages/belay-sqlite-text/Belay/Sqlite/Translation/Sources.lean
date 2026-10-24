import Belay.Sqlite.Translation.QueryExpression

set_option doc.verso true

/-! The FROM clause of a SELECT: its first table and its joins. The port of
{lit}`belay/sqlite/syntax_sources.py`: a reference is a table, or a table-valued function with
its arguments, with an optional alias; a join keeps the keywords of its operator as written, its
reference, and its optional ON condition and USING column names. -/

namespace Belay.Sqlite.Translation

open Belay.Sqlite.Model

/-- One source of a {lit}`seltablist`: its joined prefix, name, schema, alias and constraint nodes, and
the mapped arguments of a table-valued function, or none for a table. -/
structure SourceParts where
  /-- The {lit}`stl_prefix` node: the sources before this one and the join operator. -/
  joined : ParseNode
  /-- The table's or function's name. -/
  table : ParseNode
  /-- The schema name, empty when absent. -/
  schema : ParseNode
  /-- The {lit}`as` node. -/
  aliasNode : ParseNode
  /-- The {lit}`on_using` node. -/
  constraint : ParseNode
  /-- The arguments of a table-valued function. -/
  arguments : Option (Located (List Syntax.Expr))
  /-- The indexed SELECT of a derived table, or none for a named table or function. -/
  query : Option (Located Nat) := none
  deriving Inhabited

/-- The parts of one source; {lit}`INDEXED BY` is refused. A SELECT is added to the indexed query list. Like the Python
translation, the function arguments are mapped while the list is walked from its end. -/
def sourceParts (mappers : Mappers) (tree : SqlTree) (node : ParseNode) : TranslateM SourceParts := do
  let parts := tree.children node
  match tree.symbols node with
  | ["stl_prefix", "nm", "dbnm", "as", "on_using"] =>
    return ⟨parts[0]!, parts[1]!, parts[2]!, parts[3]!, parts[4]!, none, none⟩
  | ["stl_prefix", "nm", "dbnm", "LP", "exprlist", "RP", "as", "on_using"] =>
    let listed := parts[4]!
    let items ← if listed.children.isEmpty then pure #[] else
      leftList tree (tree.children listed)[0]! [(1, ["expr"]), (3, ["nexprlist", "COMMA", "expr"])]
    let arguments ← items.mapM fun item => mappers.expression tree (last item)
    return ⟨parts[0]!, parts[1]!, parts[2]!, parts[6]!, parts[7]!,
      some (sequence arguments listed.start parts[5]!.start), none⟩
  | ["stl_prefix", "LP", "select", "RP", "as", "on_using"] =>
    let select := parts[2]!
    let index ← lift mappers tree select
    return { joined := parts[0]!, table := select, schema := default, aliasNode := parts[4]!,
             constraint := parts[5]!, arguments := none, query := some (leaf index select.start select.stop) }
  | _ => unsupported node ("This FROM source is not modeled; use a table, table-valued function or SELECT")

/-- A named table, function or indexed query with its optional alias; a schema name is refused. -/
def tableReference (tree : SqlTree) (source : SourceParts) : TranslateM (Located Syntax.TableReference) := do
  absent source.schema "A schema name"
  let table ← if source.query.isSome then pure (leaf (name! "") source.table.start source.table.stop)
    else identifierName tree source.table
  let named ← alias tree source.aliasNode
  let arguments := (source.arguments.map (·.present)).getD (missing source.table.start source.table.stop)
  let query := (source.query.map (·.present)).getD (missing source.table.start source.table.stop)
  return composite { table := table.value, alias := named.value, arguments := arguments.value, query := query.value } source.table.start
    (max source.table.stop source.aliasNode.stop) #[table.span, named.span, arguments.span, query.span]

/-- The keywords of a {lit}`joinop` before {lit}`JOIN`, as written; none for {lit}`,` and a plain
{lit}`JOIN`. -/
def joinOperator (tree : SqlTree) (node : ParseNode) : Located (List String) :=
  let words := (tree.children node).filter (fun part => part.symbol != "COMMA" && part.symbol != "JOIN")
  sequence (words.map fun part => leaf (tree.text part) part.start part.stop) node.start node.stop

/-- The ON condition and the USING column names of an {lit}`on_using` node, each absent at the
node's range without its clause. -/
def joinConstraint (mappers : Mappers) (tree : SqlTree) (node : ParseNode) :
    TranslateM (Located (Option Syntax.Expr) × Located (Option (List Identifier))) := do
  let parts := tree.children node
  match tree.symbols node with
  | ["ON", "expr"] => return ((← mappers.expression tree parts[1]!).present, missing node.start node.stop)
  | ["USING", "LP", "idlist", "RP"] =>
    let items ← leftList tree parts[2]! [(1, ["nm"]), (3, ["idlist", "COMMA", "nm"])]
    let names ← items.mapM fun item => identifierName tree (last item)
    return (missing node.start node.stop, (sequence names parts[2]!.start parts[2]!.stop).present)
  | _ => return (missing node.start node.stop, missing node.start node.stop)

/-- The first source of a {lit}`seltablist` and its joins in order. -/
def fromClause (mappers : Mappers) (tree : SqlTree) (tables : ParseNode) :
    TranslateM (Located Syntax.TableReference × Located (List Syntax.Join)) := do
  let mut items : Array (ParseNode × SourceParts) := #[]
  let mut current := tables
  let mut fuel := tree.nodes.size + 1
  while fuel > 0 do
    fuel := fuel - 1
    let parts ← sourceParts mappers tree current
    items := items.push (current, parts)
    if parts.joined.children.isEmpty then break
    current := (← require tree parts.joined ["seltablist", "joinop"])[0]!
  items := items.reverse
  let (firstNode, firstParts) := items[0]!
  absent firstParts.constraint "ON or USING on the first table"
  let first ← tableReference tree firstParts
  let mut joins : Array (Located Syntax.Join) := #[]
  for (node, source) in items.extract 1 items.size do
    let operator := (← require tree source.joined ["seltablist", "joinop"])[1]!
    let (condition, usingColumns) ← joinConstraint mappers tree source.constraint
    let reference ← tableReference tree source
    let keywords := joinOperator tree operator
    let join : Syntax.Join :=
      { operator := keywords.value, source := reference.value, condition := condition.value,
        usingColumns := usingColumns.value }
    joins := joins.push (composite join operator.start node.stop
      #[keywords.span, reference.span, condition.span, usingColumns.span])
  return (first, sequence joins firstNode.stop tables.stop)

end Belay.Sqlite.Translation
