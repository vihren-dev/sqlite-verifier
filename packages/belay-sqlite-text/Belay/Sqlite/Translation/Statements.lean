import Belay.Sqlite.Parse
import Belay.Sqlite.ParserLibrary
import Belay.Sqlite.Translation.Schema
import Belay.Sqlite.Translation.Tables
import Belay.Sqlite.Translation.Triggers

set_option doc.verso true

/-! A parsed SQL script as the model's statement syntax with ranges (ADR 0017, S1, prototype 2,
candidate A). The port of {lit}`commands`, {lit}`statement` and {lit}`statements` of
{lit}`belay/sqlite/syntax.py`, and of the refusals of {lit}`sql_tree.py`'s parse. -/

namespace Belay.Sqlite.Translation

open Belay.Sqlite.Model

/-- The commands of the script in text order; a wrapper such as EXPLAIN is refused. -/
def commands (tree : SqlTree) (root : Nat) : TranslateM (Array ParseNode) := do
  let mut result : Array ParseNode := #[]
  let mut pending : Array ParseNode := #[tree.nodes[root]!]
  let mut fuel := tree.nodes.size + 1
  while fuel > 0 do
    fuel := fuel - 1
    let some node := pending.back? | break
    pending := pending.pop
    pending := pending ++ (tree.children node).reverse
    if node.symbol != "ecmd" then continue
    match tree.symbols node with
    | ["SEMI"] => pure ()
    | ["cmdx", "SEMI"] => result := result.push (tree.children (tree.children node)[0]!)[0]!
    | _ => unsupported node "Unsupported command wrapper, such as EXPLAIN; remove it"
  return result

/-- One command as a statement, after {lit}`statement` numbered its parameters, or the refusal
of a statement that has no syntax constructor. -/
def statementSyntax (tree : SqlTree) (command : ParseNode) : TranslateM (Located Syntax.Statement) := do
  let symbols := tree.symbols command
  if symbols == ["create_table", "create_table_args"] then return ← createTable tree command
  if symbols.take 3 == ["createkw", "uniqueflag", "INDEX"] then return ← createIndex tree command
  if symbols.take 2 == ["ALTER", "TABLE"] then return ← addColumn tree command
  if symbols == ["createkw", "trigger_decl", "BEGIN", "trigger_cmd_list", "END"] then return ← createTrigger tree command
  if [["DROP", "TABLE"], ["DROP", "INDEX"], ["DROP", "TRIGGER"]].contains (symbols.take 2) then return ← drop tree command
  if [["BEGIN"], ["COMMIT"], ["END"], ["ROLLBACK"]].contains (symbols.take 1) then return ← transaction tree command
  if symbols.take 2 == ["with", "insert_cmd"] then return ← insert tree command
  if symbols.take 2 == ["with", "UPDATE"] then return ← update tree command
  if symbols.take 2 == ["with", "DELETE"] then return ← delete tree command
  if symbols == ["select"] then
    let (clauses, items) ← statementSubqueries (queryClauses tree (tree.children command)[0]!)
    let subqueries := subqueryList items command
    return composite (.select clauses.columns.value clauses.source.value clauses.joins.value clauses.filter.value
        clauses.groupBy.value clauses.orderBy.value clauses.limit.value clauses.offset.value subqueries.value
        clauses.having.value clauses.distinct.value clauses.compound.value)
      command.start command.stop (clauses.selectSpans subqueries)
  if symbols.take 1 == ["PRAGMA"] then return ← pragma tree command
  unsupported command ("This statement is not modeled; the model runs CREATE TABLE, CREATE INDEX, " ++
    "CREATE TRIGGER, ALTER TABLE ADD COLUMN, DROP TABLE, DROP INDEX, DROP TRIGGER, BEGIN, COMMIT, " ++
    "ROLLBACK, INSERT, UPDATE, DELETE, SELECT and PRAGMA foreign_keys")

/-- One command as a statement with its parameter tokens: the tokens are numbered first
({name}`numberParameters`), so that each parameter expression reads its number. -/
def statement (tree : SqlTree) (command : ParseNode) : TranslateM ParameterizedStatement := do
  let parameters ← match numberParameters Limits.documentedDefaults.variableNumber tree command with
    | .ok parameters => pure parameters
    | .error refusal => throw refusal
  modify ({ · with parameters := parameters.map fun parameter => (parameter.start, parameter.number) })
  return { statement := ← statementSyntax tree command, parameters }

/-- Every command of a parsed script as a statement with its parameter tokens, in order. -/
def statements (tree : SqlTree) (root : Nat) : TranslateM (Array ParameterizedStatement) := do
  (← commands tree root).mapM (statement tree)

/-- The refusal of a text that SQLite's grammar rejects at the byte offset. -/
def inputError (offset : Nat) : Refusal :=
  { status := "INPUT_ERROR", start := offset, stop := 0,
    message := "SQLite's grammar rejects the SQL at this offset; correct the SQL there and run the command again" }

/-- The refusal of a text that exceeds the parser's limits; the parser stopped at the byte offset
and did not decide whether the text is valid SQL. -/
def resourceLimit (offset : Nat) : Refusal :=
  { status := "UNVERIFIED", start := offset, stop := 0,
    message := "SQL exceeds the parser's limits of 1 MiB of input and 200,000 syntax-tree nodes; " ++
      "split the SQL into smaller files" }

/-- The translation of a parse result: the statements with their ranges and parameter tokens, or
the refusal, with the statuses and messages of the Python frontend for a grammar error and the
parser's limits. -/
def translateParse (sql : ByteArray) : ParseResult → Except Refusal (Array ParameterizedStatement)
  | .parsed nodes root => (statements { sql, nodes } root).run' {}
  | .inputError offset => throw (inputError offset)
  | .resourceLimit offset => throw (resourceLimit offset)

/-- The translation of SQL text, as its bytes, with a grammar of the parser library: the
statements with their ranges and parameter tokens, or the refusal. It fails when the library
gives an unusable document. For example, {lit}`translate grammar "SELECT :a;".toUTF8` gives
one statement with the parameter {lit}`:a` of number 1 at bytes 7 to 9. -/
def translate (grammar : String) (sql : ByteArray) :
    IO (Except Refusal (Array ParameterizedStatement)) := do
  let document ← ParserLibrary.parse grammar sql
  let parse ← IO.ofExcept ((decodeParse grammar sql.size document).mapError IO.userError)
  return translateParse sql parse

end Belay.Sqlite.Translation
