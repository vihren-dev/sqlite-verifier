import Belay.Sqlite.QueryBridge
import Belay.Sqlite.Model

set_option doc.verso true

/-! The query form {lit}`SELECT 1 FROM pragma_table_info('t') WHERE p` over every database (ADR 0017, S4): a statement of
the schema, such as "the table {lit}`t` has a column {lit}`c`". When the catalog of the database has no table with the name of
the function, the table lookup is by the name of the argument ({lit}`Catalog.tableInfoRows`), and {lit}`p` resolves in the
scope of the pragma, the claims {lit}`Holds` and {lit}`Empty` of the query are statements about the rows of the pragma and
the resolved condition, when the expressions of {lit}`p` are calm. Then {lit}`Fails` does not hold. -/

namespace Belay.Sqlite
open Belay.Sqlite.Model

/-- For every script whose first statement is {lit}`SELECT 1 FROM pragma_table_info('t') WHERE p` (or without
{lit}`WHERE`), where the catalog of the database has no table with the name of the function, gives rows for the table
{lit}`t` ({name}`Catalog.tableInfoRows`), and {lit}`p` resolves in the scope of the pragma ({name}`tableInfoScope`), the output
of the script is the output of the step of the simple query of the pragma source with those rows. Proof sketch:
{name}`Script.outputOn_query` with the resolution of {name}`resolveStatement_select_one_tableInfo`. -/
theorem Script.outputOn_selectOne_tableInfo
    {script : Script} {db : Database} {reference : Syntax.TableReference}
    {filter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {argument : List UInt8} {rows : List (List Value)} {condition : Option Resolved.Expr}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] (some reference) [] filter [] [] none none []
      none false none, parameters) :: rest)
    (arguments : reference.arguments = some [.string argument])
    (isFunction : reference.table.isKeyword (bytes! "pragma_table_info") = true)
    (notTable : db.raw.catalog.findTable reference.table = none)
    (info : db.raw.catalog.tableInfoRows ⟨argument⟩ = some rows)
    (resolves : FilterResolves runContext.profile.dqsDml (tableInfoScope reference argument rows) [] filter condition) :
    script.outputOn db = some (resolvedStepOutput none 0 db.raw.connection parameters
      (.query (Resolved.Query.simple [Resolved.QuerySource.pragma (pragmaSource reference argument tableInfoNames rows).1] condition
        [.scalar (.literal (.integer 1))] ["1"]) [])) :=
  Script.outputOn_query script db _ parameters rest _ [] _ head
    (resolveStatement_select_one_tableInfo runContext db.raw.connection.resolveState reference argument rows filter condition
      arguments isFunction notTable info resolves)

/-- For every query script as in {name}`Script.outputOn_selectOne_tableInfo` whose condition resolves to a calm condition
(no fallible call, no clock read and no counter read): {name}`Holds` of the script on the database means that the condition
is true for some row of the pragma, evaluated in the context of the values. A row of the pragma is a row of
{name}`Catalog.tableInfoRows` with the argument and NULL as its two hidden cells. Without {lit}`WHERE`, it means that the
pragma has a row. Proof sketch: {name}`Script.outputOn_selectOne_tableInfo` and
{name}`resolvedStepOutput_simplePragma_hasRows`. -/
theorem Holds.iff_selectOne_tableInfo
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {filter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {argument : List UInt8} {rows : List (List Value)} {condition : Option Resolved.Expr}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] (some reference) [] filter [] [] none none []
      none false none, parameters) :: rest)
    (arguments : reference.arguments = some [.string argument])
    (isFunction : reference.table.isKeyword (bytes! "pragma_table_info") = true)
    (notTable : db.raw.catalog.findTable reference.table = none)
    (info : db.raw.catalog.tableInfoRows ⟨argument⟩ = some rows)
    (resolves : FilterResolves runContext.profile.dqsDml (tableInfoScope reference argument rows) [] filter condition)
    (calm : ∀ expression ∈ condition.toList, expression.Calm) :
    Holds script db isQuery ↔
      ∃ row ∈ rows.map (· ++ [Value.text argument, Value.null]), condition.all
        (fun expression => Resolved.truthy (expression.eval (Resolved.EvalContext.bound parameters) row)) = true := by
  unfold Holds
  rw [Script.outputOn_selectOne_tableInfo head arguments isFunction notTable info resolves, Option.any_some]
  exact resolvedStepOutput_simplePragma_hasRows 0 db.raw.connection parameters _ _ condition _ _
    (Resolved.Statement.Calm.selectOne_pragma _ condition calm)

/-- For every query script as in {name}`Holds.iff_selectOne_tableInfo`: {name}`Empty` of the script on the database means
that the condition is not true for any row of the pragma. Proof sketch: {name}`Script.outputOn_selectOne_tableInfo` and
{name}`resolvedStepOutput_simplePragma_hasNoRows`. -/
theorem Empty.iff_selectOne_tableInfo
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {filter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {argument : List UInt8} {rows : List (List Value)} {condition : Option Resolved.Expr}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] (some reference) [] filter [] [] none none []
      none false none, parameters) :: rest)
    (arguments : reference.arguments = some [.string argument])
    (isFunction : reference.table.isKeyword (bytes! "pragma_table_info") = true)
    (notTable : db.raw.catalog.findTable reference.table = none)
    (info : db.raw.catalog.tableInfoRows ⟨argument⟩ = some rows)
    (resolves : FilterResolves runContext.profile.dqsDml (tableInfoScope reference argument rows) [] filter condition)
    (calm : ∀ expression ∈ condition.toList, expression.Calm) :
    Empty script db isQuery ↔
      ∀ row ∈ rows.map (· ++ [Value.text argument, Value.null]), condition.all
        (fun expression => Resolved.truthy (expression.eval (Resolved.EvalContext.bound parameters) row)) = false := by
  unfold Empty
  rw [Script.outputOn_selectOne_tableInfo head arguments isFunction notTable info resolves, Option.any_some]
  exact resolvedStepOutput_simplePragma_hasNoRows 0 db.raw.connection parameters _ _ condition _ _
    (Resolved.Statement.Calm.selectOne_pragma _ condition calm)

/-- For every query script as in {name}`Holds.iff_selectOne_tableInfo`, {name}`Fails` of the script on the database does
not hold. Proof sketch: {name}`Script.outputOn_selectOne_tableInfo` and {name}`resolvedStepOutput_simplePragma_not_isError`. -/
theorem Fails.not_selectOne_tableInfo
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {filter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {argument : List UInt8} {rows : List (List Value)} {condition : Option Resolved.Expr}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] (some reference) [] filter [] [] none none []
      none false none, parameters) :: rest)
    (arguments : reference.arguments = some [.string argument])
    (isFunction : reference.table.isKeyword (bytes! "pragma_table_info") = true)
    (notTable : db.raw.catalog.findTable reference.table = none)
    (info : db.raw.catalog.tableInfoRows ⟨argument⟩ = some rows)
    (resolves : FilterResolves runContext.profile.dqsDml (tableInfoScope reference argument rows) [] filter condition)
    (calm : ∀ expression ∈ condition.toList, expression.Calm) :
    ¬ Fails script db isQuery := by
  unfold Fails
  rw [Script.outputOn_selectOne_tableInfo head arguments isFunction notTable info resolves, Option.any_some]
  have notError := resolvedStepOutput_simplePragma_not_isError 0 db.raw.connection parameters (tableInfoNames.length + 2)
    (rows.map (· ++ [Value.text argument, Value.null])) condition _ _
    (Resolved.Statement.Calm.selectOne_pragma _ condition calm)
  simpa [pragmaSource] using notError

end Belay.Sqlite
