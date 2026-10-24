import Belay.Sqlite.QueryBridge
import Belay.Sqlite.Model

set_option doc.verso true

/-! The query form {lit}`SELECT 1 FROM t WHERE p` over every database (ADR 0017, S4): "some row of
{lit}`t` satisfies {lit}`p`". When the catalog of the database has the table and {lit}`p` resolves in
the scope of the table, the claims {lit}`Holds` and {lit}`Empty` of the query are statements about the
rows of the table and the resolved condition, and {lit}`Fails` does not hold. When the catalog has no
table of that name, {lit}`Fails` holds, and the other two do not. -/

namespace Belay.Sqlite

open Belay.Sqlite.Model

/-- For every script whose first statement is {lit}`SELECT 1 FROM t WHERE p` (or without
{lit}`WHERE`), where the catalog of the database has the table {lit}`t` at a position and
the condition resolves, the output of the script is the output of the step of the simple query of
that table. The source reference has no indexed query.
Proof sketch: {name}`Script.outputOn_query` with the resolution of
{name}`resolveStatement_select_one_from`. -/
theorem Script.outputOn_selectOne {script : Script} {db : Database} {reference : Syntax.TableReference}
    {filter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {position : Nat} {table : CatalogTable} {condition : Option Resolved.Expr}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] (some reference) [] filter [] [] none none []
      none false none, parameters) :: rest)
    (namedSource : reference.query = none) (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (resolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table) [] filter
      condition) :
    script.outputOn db = some (resolvedStepOutput none 0 db.raw.connection parameters
      (.query (Resolved.Query.simple [Resolved.QuerySource.first position] condition
        [.scalar (.literal (.integer 1))] ["1"]) [])) :=
  Script.outputOn_query script db _ parameters rest _ [] _ head
    (resolveStatement_select_one_from runContext db.raw.connection.resolveState reference filter position table condition
      namedSource arguments found resolves)

/-- For every query script whose first statement is {lit}`SELECT 1 FROM t WHERE p`, where the catalog
of the database has the table {lit}`t` and {lit}`p` resolves to a calm condition (it has no
fallible call, no clock and no counter read): {lit}`Holds` of the script on the database means that
the condition is true for some row of the table in scan order (rowid order, or primary-key order for a {lit}`WITHOUT ROWID` table), evaluated in the context of the
values. Without {lit}`WHERE`, it means that the table has a row. The source reference has no indexed query.
Proof sketch:
{name}`Script.outputOn_selectOne` and {name}`resolvedStepOutput_simpleTable_hasRows`. -/
theorem Holds.iff_selectOne
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {filter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {position : Nat} {table : CatalogTable} {condition : Option Resolved.Expr}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] (some reference) [] filter [] [] none none []
      none false none, parameters) :: rest)
    (namedSource : reference.query = none) (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (resolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table) [] filter
      condition)
    (calm : ∀ expression ∈ condition.toList, expression.Calm) :
    Holds script db isQuery ↔
      ∃ row ∈ Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] },
        condition.all (fun expression => Resolved.truthy (expression.eval (Resolved.EvalContext.bound parameters) row)) = true := by
  unfold Holds
  rw [Script.outputOn_selectOne head namedSource arguments found resolves, Option.any_some]
  exact resolvedStepOutput_simpleTable_hasRows 0 position db.raw.connection parameters
    { shape := table, rows := db.raw.rows.getD position [] } condition _ _ (Database.table_of_findTable db.raw _ position table found)
    (Resolved.Statement.Calm.selectOne position condition calm)

/-- For every query script as in {name}`Holds.iff_selectOne`: {lit}`Empty` of the script on the
database means that the condition is not true for any row of the table. The source reference has no indexed query.
Proof sketch:
{name}`Script.outputOn_selectOne` and {name}`resolvedStepOutput_simpleTable_hasNoRows`. -/
theorem Empty.iff_selectOne
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {filter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {position : Nat} {table : CatalogTable} {condition : Option Resolved.Expr}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] (some reference) [] filter [] [] none none []
      none false none, parameters) :: rest)
    (namedSource : reference.query = none) (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (resolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table) [] filter
      condition)
    (calm : ∀ expression ∈ condition.toList, expression.Calm) :
    Empty script db isQuery ↔
      ∀ row ∈ Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] },
        condition.all (fun expression => Resolved.truthy (expression.eval (Resolved.EvalContext.bound parameters) row)) = false := by
  unfold Empty
  rw [Script.outputOn_selectOne head namedSource arguments found resolves, Option.any_some]
  exact resolvedStepOutput_simpleTable_hasNoRows 0 position db.raw.connection parameters
    { shape := table, rows := db.raw.rows.getD position [] } condition _ _ (Database.table_of_findTable db.raw _ position table found)
    (Resolved.Statement.Calm.selectOne position condition calm)

/-- For every query script as in {name}`Holds.iff_selectOne`, {lit}`Fails` of the script on the
database does not hold: a calm query of a table that exists neither fails to resolve nor fails to
run. The source reference has no indexed query.
Proof sketch: {name}`Script.outputOn_selectOne` and {name}`resolvedStepOutput_simpleTable_not_isError`. -/
theorem Fails.not_selectOne
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {filter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {position : Nat} {table : CatalogTable} {condition : Option Resolved.Expr}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] (some reference) [] filter [] [] none none []
      none false none, parameters) :: rest)
    (namedSource : reference.query = none) (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (resolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table) [] filter
      condition)
    (calm : ∀ expression ∈ condition.toList, expression.Calm) :
    ¬ Fails script db isQuery := by
  unfold Fails
  rw [Script.outputOn_selectOne head namedSource arguments found resolves, Option.any_some,
    resolvedStepOutput_simpleTable_not_isError 0 position db.raw.connection parameters
    { shape := table, rows := db.raw.rows.getD position [] } condition _ _ (Database.table_of_findTable db.raw _ position table found)
    (Resolved.Statement.Calm.selectOne position condition calm)]
  simp

/-- For every query script whose first statement is {lit}`SELECT 1 FROM t WHERE p` (with any
{lit}`WHERE`), where the catalog of the database has no table {lit}`t`, and {lit}`t` is neither a
table of SQLite itself ({name}`reservedName`) nor a table-valued function ({name}`eponymousName`):
{lit}`Fails` of the script holds, because SQLite refuses to prepare the statement ({lit}`no such
table`). Then neither {lit}`Holds` nor {lit}`Empty` holds ({name}`Holds.not_fails`,
{name}`Empty.not_fails`). The source reference has no indexed query.
Proof sketch: {name}`resolveStatement_select_missing_table` gives the
prepare error, and {name}`resolvedStepOutput_prepareError` the error output. -/
theorem Fails.selectOne_missing {script : Script} {db : Database} {isQuery : script.isQuery = true}
    {reference : Syntax.TableReference} {filter : Option Syntax.Expr} {parameters : List Value}
    {rest : List (Syntax.Statement × List Value)}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] (some reference) [] filter [] [] none none []
      none false none, parameters) :: rest)
    (namedSource : reference.query = none) (arguments : reference.arguments = none) (missing : db.raw.catalog.findTable reference.table = none)
    (notReserved : reservedName reference.table = false) (notFunction : eponymousName reference.table = false) :
    Fails script db isQuery := by
  unfold Fails
  rw [Script.outputOn_eq_step script db _ parameters rest head,
    resolveStatement_select_missing_table runContext db.raw.connection.resolveState
      { columns := [.expression (.numeric "1") none "1"], source := some reference, joins := [], filter,
        groupBy := [], orderBy := [], limit := none, offset := none, parent := none, having := none, distinct := false,
        compound := none } reference rfl rfl namedSource arguments missing notReserved notFunction,
    Option.any_some]
  simp only []
  rw [resolvedStepOutput_prepareError]
  rfl

end Belay.Sqlite
