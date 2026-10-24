import Belay.Sqlite.CountQuery
import Belay.Sqlite.SqlSimpLaws
import Belay.Sqlite.Model

set_option doc.verso true

/-! The bound of a unique lookup over every database (ADR 0017, S4): the query
{lit}`SELECT 1 WHERE (SELECT count(*) FROM t WHERE c = $v) <= 1` holds when {lit}`c` is the one column of a unique
key of {lit}`t`, the key has the collation of the comparison, and the value {lit}`$v` has no affinity of its own. The
bound reads the stored proof of validity of the database: its unique keys and the stored form of its cells. -/

namespace Belay.Sqlite
open Belay.Sqlite.Model

/-- For every script {lit}`SELECT 1 WHERE (SELECT count(*) FROM t WHERE c = $v) <= 1`, where the catalog of the database has
the table {lit}`t` at a position, {lit}`c = $v` resolves in the scope of the table to the comparison of the cell at
position {lit}`index` with a parameter, with the affinity of the column and a collation, and {lit}`<= 1` resolves to the
comparison of the subquery value with the integer 1: if the table has a unique key without filter whose one term is the
column at {lit}`index` under that same collation, the script holds on the database. Then at most one row of the table
has a cell equal to the value after the affinity of the column, so the number of rows is at most one.
The statement needs the collation of the comparison to be the collation of the key: with a column {lit}`COLLATE NOCASE` and a
unique index {lit}`COLLATE BINARY` a table can hold {lit}`'a'` and {lit}`'A'`, and {lit}`c = 'a'` then matches both rows.
The source reference has no indexed query.
Proof sketch: {name}`Holds.iff_selectOne_count` turns the claim into the truth of the condition {lit}`n <= 1` for the number of
rows ({name}`Resolved.truthy_count_le_one`); the unique lookup bounds that number
({name}`Table.KeysUnique.countMatching_le_one`) with the unique keys and the stored cells of the valid database. -/
theorem Holds.selectOne_count_unique_lookup
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {subFilter mainFilter : Syntax.Expr} {parameters : List Value}
    {rest : List (Syntax.Statement × List Value)} {position : Nat} {table : CatalogTable}
    {name : String} {text : String} {index slot : Nat} {descending : Bool} {collation : Collation}
    {column : CatalogColumn} {key : UniqueKey}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some mainFilter) [] [] none none
      [Syntax.Subquery.mk [.expression (.callStar name) none text] (some reference) [] (some subFilter) [] [] none none none none
        false none] none false none, parameters) :: rest)
    (count : normalizeIdentifier name = "count")
    (namedSource : reference.query = none) (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (subResolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table) []
      (some subFilter) (some (.compare .eq (some column.affinity) (.column index) (.parameter slot) collation))
      { current := some 0 })
    (mainResolves : ∀ lowest : Option Nat,
      FilterResolves runContext.profile.dqsDml [] [] (some mainFilter)
        (some (.compare .le none (.subquery 0) (.literal (.integer 1)) .binary)) { later := [countShape lowest] })
    (member : key ∈ db.raw.catalog.uniqueKeys position table) (columnAt : table.columns[index]? = some column)
    (noFilter : key.filter = none)
    (oneTerm : key.terms = [{ term := .column index, descending, collation }]) :
    Holds script db isQuery := by
  have present := Database.table_of_findTable db.raw _ position table found
  refine (Holds.iff_selectOne_count head count namedSource arguments found subResolves mainResolves (by simp [sql_simp])
    (by simp [sql_simp])).2 ?_
  rw [Resolved.truthy_count_le_one]
  simpa using Table.KeysUnique.countMatching_le_one (db.valid.unique position _ present)
    (db.valid.admitted.rowsStored position _ present) member columnAt noFilter oneTerm
    (Resolved.EvalContext.bound parameters) (.parameter slot) (parameterValue parameters slot) fun _ => rfl

end Belay.Sqlite
