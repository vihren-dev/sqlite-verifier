import Belay.Sqlite.Translation.Writes

set_option doc.verso true

/-! CREATE TRIGGER. The port of {lit}`belay/sqlite/syntax_triggers.py`: a trigger keeps its
name, {lit}`IF NOT EXISTS`, its time, its event, its table, its {lit}`WHEN` condition and its
body statements, each with the fields of its {lit}`Syntax.BodyStatement` constructor. -/

namespace Belay.Sqlite.Translation

open Belay.Sqlite.Model

/-- The refusal of a subquery in {lit}`WHEN`. -/
def inWhen : String :=
  "A subquery in the WHEN condition of a trigger is not modeled; move the test into the trigger's statements"

/-- The table of a body statement, a {lit}`trnm` node; a qualified name is refused, as SQLite
refuses it inside a trigger. -/
def bodyTable (tree : SqlTree) (node : ParseNode) : TranslateM (Located Identifier) := do
  unless tree.symbols node == ["nm"] do
    unsupported node "A qualified table name is not allowed in a trigger; write the table name"
  identifierName tree (tree.children node)[0]!

/-- The optional WHERE filter of a {lit}`where_opt` node, absent at the node without it. -/
def bodyFilter (tree : SqlTree) (whereNode : ParseNode) : TranslateM (Located (Option Syntax.Expr)) := do
  let parts := tree.children whereNode
  if parts.isEmpty then return missing whereNode.start whereNode.stop
  Located.present <$> queryExpression tree parts[1]!

/-- {lit}`INSERT [OR algorithm] INTO table [(columns)] VALUES rows [ON CONFLICT ...]` and
{lit}`REPLACE INTO` in a trigger body. -/
def bodyInsert (tree : SqlTree) (node : ParseNode) : TranslateM (Located Syntax.BodyStatement) := do
  let parts ← require tree node ["scanpt", "insert_cmd", "INTO", "trnm", "idlist_opt", "select", "upsert", "scanpt"]
  let (conflicts, returned) ← noSubqueries
    "A subquery in ON CONFLICT is not modeled; read the value in a separate statement" (conflictClauses tree parts[6]!)
  unless returned.isEmpty do unsupported parts[6]! "RETURNING is not allowed in a trigger; remove it"
  let columns ← columnList tree parts[4]!
  let (rows, items) ← statementSubqueries (valueRows tree parts[5]!)
  let table ← bodyTable tree parts[3]!
  let algorithm ← insertAlgorithm tree parts[1]!
  let subqueries := subqueryList items node
  return composite (.insert table.value columns.value rows.value conflicts.value algorithm.value subqueries.value)
    node.start node.stop #[table.span, columns.span, rows.span, conflicts.span, algorithm.span, subqueries.span]

/-- {lit}`UPDATE table SET assignments [WHERE expression]` in a trigger body. -/
def bodyUpdate (tree : SqlTree) (node : ParseNode) : TranslateM (Located Syntax.BodyStatement) := do
  let parts ← require tree node ["UPDATE", "orconf", "trnm", "tridxby", "SET", "setlist", "from", "where_opt", "scanpt"]
  absent parts[1]! "An OR conflict clause of UPDATE"
  absent parts[3]! "INDEXED BY"
  absent parts[6]! "UPDATE FROM"
  let ((mapped, filter), items) ← statementSubqueries do
    let mapped ← assignmentList tree parts[5]!
    return (mapped, ← bodyFilter tree parts[7]!)
  let table ← bodyTable tree parts[2]!
  let subqueries := subqueryList items node
  return composite (.update table.value mapped.value filter.value subqueries.value) node.start node.stop
    #[table.span, mapped.span, filter.span, subqueries.span]

/-- {lit}`DELETE FROM table [WHERE expression]` in a trigger body. -/
def bodyDelete (tree : SqlTree) (node : ParseNode) : TranslateM (Located Syntax.BodyStatement) := do
  let parts ← require tree node ["DELETE", "FROM", "trnm", "tridxby", "where_opt", "scanpt"]
  absent parts[3]! "INDEXED BY"
  let (filter, items) ← statementSubqueries (bodyFilter tree parts[4]!)
  let table ← bodyTable tree parts[2]!
  let subqueries := subqueryList items node
  return composite (.delete table.value filter.value subqueries.value) node.start node.stop
    #[table.span, filter.span, subqueries.span]

/-- A SELECT in a trigger body, with every clause of {lit}`Syntax.BodyStatement.select`; a
compound SELECT there is refused. -/
def bodySelect (tree : SqlTree) (node : ParseNode) : TranslateM (Located Syntax.BodyStatement) := do
  let parts ← require tree node ["scanpt", "select", "scanpt"]
  let (clauses, items) ← statementSubqueries (queryClauses tree parts[1]!)
  if clauses.compound.value.isSome then
    unsupported node "A compound SELECT in a trigger body is not modeled; write one SELECT there"
  let subqueries := subqueryList items node
  return composite (.select clauses.columns.value clauses.source.value clauses.joins.value clauses.filter.value
      clauses.groupBy.value clauses.orderBy.value clauses.limit.value clauses.offset.value subqueries.value
      clauses.having.value clauses.distinct.value)
    node.start node.stop (clauses.leading ++ #[subqueries.span, clauses.having.span, clauses.distinct.span])

/-- The statements of a {lit}`trigger_cmd_list` node in text order. -/
def body (tree : SqlTree) (node : ParseNode) : TranslateM (Located (List Syntax.BodyStatement)) := do
  let items ← leftList tree node [(2, ["trigger_cmd", "SEMI"]), (3, ["trigger_cmd_list", "trigger_cmd", "SEMI"])]
  let statements ← items.mapM fun item => do
    let command := fromEnd item 2
    let symbols := tree.symbols command
    match symbols.head? with
    | some "UPDATE" => bodyUpdate tree command
    | some "DELETE" => bodyDelete tree command
    | _ => if (symbols.drop 1).take 1 == ["insert_cmd"] then bodyInsert tree command else bodySelect tree command
  return sequence statements node.start node.stop

/-- {lit}`before` for BEFORE and for a trigger without a time, {lit}`after` for AFTER; INSTEAD OF,
which needs a view, is refused. -/
def triggerTime (tree : SqlTree) (node : ParseNode) : TranslateM (Located Syntax.TriggerTime) := do
  let symbols := tree.symbols node
  if symbols == ["INSTEAD", "OF"] then
    unsupported node ("INSTEAD OF triggers are not modeled, as the model has no views; " ++
      "write the statements on the tables instead")
  return leaf (if symbols == ["AFTER"] then .after else .before) node.start node.stop

/-- {lit}`insert`, {lit}`delete`, or {lit}`update` with the column names of {lit}`UPDATE OF`. -/
def triggerEvent (tree : SqlTree) (node : ParseNode) : TranslateM (Located Syntax.TriggerEvent) := do
  let parts := tree.children node
  match tree.symbols node with
  | ["INSERT"] => return leaf .insert node.start node.stop
  | ["DELETE"] => return leaf .delete node.start node.stop
  | symbols =>
    let columns ← if symbols == ["UPDATE", "OF", "idlist"] then do
        let items ← leftList tree parts[2]! [(1, ["nm"]), (3, ["idlist", "COMMA", "nm"])]
        items.mapM fun item => identifierName tree (last item)
      else pure #[]
    let listed := sequence columns node.start node.stop
    return composite (.update listed.value) node.start node.stop #[listed.span]

/-- {lit}`CREATE TRIGGER [IF NOT EXISTS] name [BEFORE|AFTER] event ON table [FOR EACH ROW]
[WHEN condition] BEGIN statements END`. -/
def createTrigger (tree : SqlTree) (command : ParseNode) : TranslateM (Located Syntax.Statement) := do
  let parts := tree.children command
  let declaration ← require tree parts[1]! ["temp", "TRIGGER", "ifnotexists", "nm", "dbnm", "trigger_time",
    "trigger_event", "ON", "fullname", "foreach_clause", "when_clause"]
  absent declaration[0]! "A TEMP trigger"
  absent declaration[4]! "A schema name"
  let table := declaration[8]!
  unless tree.symbols table == ["nm"] do unsupported table "A schema name is not modeled; remove it"
  let whenNode := declaration[10]!
  let condition ← noSubqueries inWhen do
    if whenNode.children.isEmpty then pure (missing whenNode.start whenNode.stop)
    else Located.present <$> queryExpression tree (tree.children whenNode)[1]!
  let existsNode := declaration[2]!
  let triggerName ← identifierName tree declaration[3]!
  let time ← triggerTime tree declaration[5]!
  let event ← triggerEvent tree declaration[6]!
  let tableName ← identifierName tree (tree.children table)[0]!
  let statements ← body tree parts[3]!
  return composite (.createTrigger triggerName.value (!existsNode.children.isEmpty) time.value event.value tableName.value
      condition.value statements.value) command.start command.stop
    #[triggerName.span, spanOf existsNode, time.span, event.span, tableName.span, condition.span, statements.span]

end Belay.Sqlite.Translation
