import Belay.Sqlite.QueryBridge
import Belay.Sqlite.Model

set_option doc.verso true

/-! The query form {lit}`SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM t GROUP BY k HAVING count(*) > 1)` over every
database (ADR 0017, S4): "no two rows of {lit}`t` have a key {lit}`k` that is equal". When the catalog of the database
has the table and {lit}`k` resolves in the scope of the table to a key that is calm (no fallible call, no clock read
and no counter read), the claims {lit}`Holds` and {lit}`Empty` of the query are statements about the groups that
{lit}`GROUP BY` makes of the rows of the table, and {lit}`Fails` does not hold. The grouping puts NULL keys in one
group, unlike a {lit}`UNIQUE` index, so two rows with a NULL key make {lit}`Empty` hold. -/

namespace Belay.Sqlite
open Belay.Sqlite.Model

/-- For every script whose first statement is {lit}`SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM t GROUP BY k HAVING
count(*) > 1)`, where the catalog of the database has the table {lit}`t` at a position and {lit}`k` resolves in the
scope of the table to a key under a collation ({name}`GroupTermResolves`), the output of the script is the output of
the step of the simple query without source whose condition is {lit}`NOT EXISTS` of subquery 0, with the duplicate-key
query of that table as its one subquery. Proof sketch: {name}`Script.outputOn_query` with the resolution of
{name}`resolveStatement_selectOne_notExists_duplicateKeys`. -/
theorem Script.outputOn_selectOne_noDuplicateKeys
    {script : Script} {db : Database} {reference : Syntax.TableReference} {term : Syntax.Expr}
    {parameters : List Value} {rest : List (Syntax.Statement × List Value)} {position : Nat} {table : CatalogTable}
    {key : Resolved.Expr} {collation : Collation} {name : String}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some (.not (.exists 0))) [] [] none
      none [Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] none [term] [] none none none
        (some (.compare .gt (.callStar name) (.numeric "1"))) false none] none false none, parameters) :: rest)
    (count : normalizeIdentifier name = "count")
    (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (groupResolves : GroupTermResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table)
      { current := some 0, aggregates := [.callStar name] } term key collation) :
    script.outputOn db = some (resolvedStepOutput none 0 db.raw.connection parameters
      (.query (Resolved.Query.selectOneWhere (.not (.exists 0)))
        [Resolved.Query.duplicateKeys [Resolved.QuerySource.first position] key collation])) :=
  Script.outputOn_query script db _ parameters rest _ _ _ head
    (resolveStatement_selectOne_notExists_duplicateKeys runContext db.raw.connection.resolveState reference term name count
      position table key collation arguments found groupResolves)

/-- For every script that is one read-only statement and is as in {name}`Script.outputOn_selectOne_noDuplicateKeys`,
where the key is calm: {name}`Holds` of the script on the database means that no group of the rows of the table in
scan order, grouped by the key under the collation ({name}`Resolved.groups`), has more than one row. Two rows are in
one group when their keys compare equal under the collation, and two NULL keys compare equal. An empty table has no
group. Proof sketch: {name}`Script.outputOn_selectOne_noDuplicateKeys` and
{name}`resolvedStepOutput_notExists_duplicateKeys_hasRows`. -/
theorem Holds.iff_selectOne_noDuplicateKeys
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {term : Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)} {position : Nat}
    {table : CatalogTable} {key : Resolved.Expr} {collation : Collation} {name : String}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some (.not (.exists 0))) [] [] none
      none [Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] none [term] [] none none none
        (some (.compare .gt (.callStar name) (.numeric "1"))) false none] none false none, parameters) :: rest)
    (count : normalizeIdentifier name = "count")
    (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (groupResolves : GroupTermResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table)
      { current := some 0, aggregates := [.callStar name] } term key collation)
    (keyCalm : key.Calm) :
    Holds script db isQuery ↔
      ∀ group ∈ Resolved.groups (Resolved.EvalContext.bound parameters) [(key, collation)]
        (Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] }), group.length ≤ 1 := by
  unfold Holds
  rw [Script.outputOn_selectOne_noDuplicateKeys head count arguments found groupResolves, Option.any_some]
  exact resolvedStepOutput_notExists_duplicateKeys_hasRows 0 position db.raw.connection parameters
    { shape := table, rows := db.raw.rows.getD position [] } key collation (Database.table_of_findTable db.raw _ position table found)
    (Resolved.Statement.Calm.selectOne_duplicateKeys position _ key collation ((Resolved.Expr.calm_not _).2 (Resolved.Expr.calm_exists 0)) keyCalm)

/-- For every script as in {name}`Holds.iff_selectOne_noDuplicateKeys`: {name}`Empty` of the script on the database
means that some group of the rows of the table in scan order, grouped by the key under the collation, has more than
one row: two rows of the table have keys that compare equal under the collation (two NULL keys compare equal). Proof
sketch: {name}`Script.outputOn_selectOne_noDuplicateKeys` and
{name}`resolvedStepOutput_notExists_duplicateKeys_hasNoRows`. -/
theorem Empty.iff_selectOne_noDuplicateKeys
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {term : Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)} {position : Nat}
    {table : CatalogTable} {key : Resolved.Expr} {collation : Collation} {name : String}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some (.not (.exists 0))) [] [] none
      none [Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] none [term] [] none none none
        (some (.compare .gt (.callStar name) (.numeric "1"))) false none] none false none, parameters) :: rest)
    (count : normalizeIdentifier name = "count")
    (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (groupResolves : GroupTermResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table)
      { current := some 0, aggregates := [.callStar name] } term key collation)
    (keyCalm : key.Calm) :
    Empty script db isQuery ↔
      ∃ group ∈ Resolved.groups (Resolved.EvalContext.bound parameters) [(key, collation)]
        (Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] }), 1 < group.length := by
  unfold Empty
  rw [Script.outputOn_selectOne_noDuplicateKeys head count arguments found groupResolves, Option.any_some]
  exact resolvedStepOutput_notExists_duplicateKeys_hasNoRows 0 position db.raw.connection parameters
    { shape := table, rows := db.raw.rows.getD position [] } key collation (Database.table_of_findTable db.raw _ position table found)
    (Resolved.Statement.Calm.selectOne_duplicateKeys position _ key collation ((Resolved.Expr.calm_not _).2 (Resolved.Expr.calm_exists 0)) keyCalm)

/-- For every script as in {name}`Holds.iff_selectOne_noDuplicateKeys`, {name}`Fails` of the script on the database
does not hold: a calm query of a table that exists neither fails to resolve nor fails to run. Proof sketch:
{name}`Script.outputOn_selectOne_noDuplicateKeys` and {name}`resolvedStepOutput_notExists_duplicateKeys_not_isError`. -/
theorem Fails.not_selectOne_noDuplicateKeys
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {term : Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)} {position : Nat}
    {table : CatalogTable} {key : Resolved.Expr} {collation : Collation} {name : String}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some (.not (.exists 0))) [] [] none
      none [Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] none [term] [] none none none
        (some (.compare .gt (.callStar name) (.numeric "1"))) false none] none false none, parameters) :: rest)
    (count : normalizeIdentifier name = "count")
    (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (groupResolves : GroupTermResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table)
      { current := some 0, aggregates := [.callStar name] } term key collation)
    (keyCalm : key.Calm) :
    ¬ Fails script db isQuery := by
  unfold Fails
  rw [Script.outputOn_selectOne_noDuplicateKeys head count arguments found groupResolves, Option.any_some,
    resolvedStepOutput_notExists_duplicateKeys_not_isError 0 position db.raw.connection parameters
    { shape := table, rows := db.raw.rows.getD position [] } key collation (Database.table_of_findTable db.raw _ position table found)
    (Resolved.Statement.Calm.selectOne_duplicateKeys position _ key collation ((Resolved.Expr.calm_not _).2 (Resolved.Expr.calm_exists 0)) keyCalm)]
  simp

/-- For every script as in {name}`Holds.iff_selectOne_noDuplicateKeys`: {name}`Holds` of the script on the database
means that no row of the table in scan order has a key that compares as equal, under the collation, to the key of a
row before it. In words: no two rows of the table have keys that compare as equal under the collation, and two NULL
keys compare as equal. Rows are compared with the rows before them; the test is symmetric because the comparison of
a collation is. Proof sketch: {name}`Holds.iff_selectOne_noDuplicateKeys` and {name}`Resolved.groups_short_iff_pairwise`
with {name}`Resolved.sameGroup_single`. -/
theorem Holds.iff_selectOne_noDuplicateKeys_pairwise
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {term : Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)} {position : Nat}
    {table : CatalogTable} {key : Resolved.Expr} {collation : Collation} {name : String}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some (.not (.exists 0))) [] [] none
      none [Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] none [term] [] none none none
        (some (.compare .gt (.callStar name) (.numeric "1"))) false none] none false none, parameters) :: rest)
    (count : normalizeIdentifier name = "count")
    (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (groupResolves : GroupTermResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table)
      { current := some 0, aggregates := [.callStar name] } term key collation)
    (keyCalm : key.Calm) :
    Holds script db isQuery ↔
      (Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] }).Pairwise
        fun earlier later => collation.compare (key.eval (Resolved.EvalContext.bound parameters) later)
          (key.eval (Resolved.EvalContext.bound parameters) earlier) ≠ Ordering.eq := by
  rw [Holds.iff_selectOne_noDuplicateKeys head count arguments found groupResolves keyCalm,
    Resolved.groups_short_iff_pairwise]
  simp only [Resolved.sameGroup_single, beq_eq_false_iff_ne]

/-- For every script as in {name}`Holds.iff_selectOne_noDuplicateKeys`: {name}`Empty` of the script on the database
means that some row of the table has a key that compares as equal, under the collation, to the key of a row before
it. Proof sketch: {name}`Empty.iff_selectOne_noDuplicateKeys` and {name}`Resolved.groups_long_iff_repeated` with
{name}`Resolved.sameGroup_single`. -/
theorem Empty.iff_selectOne_noDuplicateKeys_repeated
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {term : Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)} {position : Nat}
    {table : CatalogTable} {key : Resolved.Expr} {collation : Collation} {name : String}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some (.not (.exists 0))) [] [] none
      none [Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] none [term] [] none none none
        (some (.compare .gt (.callStar name) (.numeric "1"))) false none] none false none, parameters) :: rest)
    (count : normalizeIdentifier name = "count")
    (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (groupResolves : GroupTermResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table)
      { current := some 0, aggregates := [.callStar name] } term key collation)
    (keyCalm : key.Calm) :
    Empty script db isQuery ↔
      ¬ (Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] }).Pairwise
        fun earlier later => collation.compare (key.eval (Resolved.EvalContext.bound parameters) later)
          (key.eval (Resolved.EvalContext.bound parameters) earlier) ≠ Ordering.eq := by
  rw [Empty.iff_selectOne_noDuplicateKeys head count arguments found groupResolves keyCalm,
    Resolved.groups_long_iff_repeated]
  simp only [Resolved.sameGroup_single, beq_eq_false_iff_ne]

end Belay.Sqlite
