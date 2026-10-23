import Belay.Sqlite.Model.Resolution.Catalog

set_option doc.verso true

/-! The names in scope of an expression (ADR 0012, amendment 2, "Names"): the sources of
a query or the one table of a write, each with its name and columns. A joined row is
the concatenation of the cells of the sources in order, so a column has a position in
that row. -/

namespace Belay.Sqlite.Model

/-- How the join of a source that merges a column changes an unqualified name of that
column (ADR 0012, amendment 3): an inner or left join keeps the left result, a right join
takes its own column, and a full join adds its column to a coalesce. -/
inductive MergeRule where
  /-- An inner or left join: the name keeps naming the left result. -/
  | keepLeft
  /-- A right join: the name names this source's column, with its affinity. -/
  | takeRight
  /-- A full join: the name is the coalesce of the left result and this column. -/
  | coalesce
  deriving Repr, DecidableEq

/-- One named source: the name that qualifies its columns (the alias as written, else the
table name as declared, or {lit}`json_each` for that function), its columns, the position
of its first cell in the joined row, and the columns that a {lit}`USING` or {lit}`NATURAL`
join merged into a left column. -/
structure ScopeSource where
  /-- The name of the source. -/
  name : Identifier
  /-- The columns of the source's table. -/
  columns : List CatalogColumn
  /-- The position in the joined row of the source's first cell: the number of cells of
  the sources before it ({lit}`Scope.place`). 0 for the first source and for the table of a
  write. -/
  offset : Nat := 0
  /-- The positions in {name}`ScopeSource.columns` of the merged columns: {lit}`*` and
  unqualified names do not see them, and qualified names and {lit}`x.*` do. Empty for a
  source without {lit}`USING` or {lit}`NATURAL`, and for the table of a write. -/
  merged : List Nat := []
  /-- How the source's join changes an unqualified name of a merged column; the rule of
  an inner join for a source that merges nothing. -/
  mergeRule : MergeRule := .keepLeft
  /-- The positions in {name}`ScopeSource.columns` of the hidden columns, which {lit}`*` and
  {lit}`x.*` do not show and names do see: the {lit}`json` and {lit}`root` columns of
  {lit}`json_each`. Empty for a table. -/
  hidden : List Nat := []
  /-- The positions in {name}`ScopeSource.columns` of the hidden columns whose conditions SQLite
  passes to a table-valued pragma as its arguments: {lit}`arg` and {lit}`schema`. A name of one
  is the restriction {lit}`table-function`. Empty for every other source. -/
  arguments : List Nat := []
  /-- Whether the source has a rowid that {lit}`rowid`, {lit}`_rowid_` and {lit}`oid` name: a
  table that is not {lit}`WITHOUT ROWID`, and {lit}`json_each`. -/
  hasRowid : Bool := true
  /-- How many queries out the source is (ADR 0018, D1): 0 for a source of the query whose
  expressions resolution resolves, 1 for a source of the query around a subquery, and so on. -/
  depth : Nat := 0
  /-- Whether the source is a trigger's {lit}`NEW` or {lit}`OLD` row (ADR 0018, D5), which only a
  qualified name sees ({lit}`Scope.resolveQualified`); false for every other source. -/
  trigger : Bool := false
  deriving Repr, DecidableEq

/-- The sources in scope, in {lit}`FROM` order, each at its offset in the joined row;
empty where no table is in scope, as in a {lit}`VALUES` row. In a subquery the sources of the
queries around it come first, as their cells come first in its row ({name}`ScopeSource.depth`). -/
abbrev Scope := List ScopeSource

/-- The sources in order, each at the offset after the cells of the sources before it, from
{lit}`start`: 0 for a statement's query, the number of outer cells for a subquery. -/
def Scope.place (sources : List ScopeSource) (start : Nat := 0) : Scope :=
  (sources.foldl (fun (offset, placed) source =>
    (offset + source.columns.length, placed ++ [{ source with offset }])) (start, [])).2

/-- The sources of the query whose expressions resolution resolves, at depth 0. -/
def Scope.inner (scope : Scope) : Scope := scope.filter (·.depth == 0)

/-- The scope of a subquery: the sources of the scope around it, one depth further out,
followed by its own sources, which {name}`Scope.place` put after the outer cells. -/
def Scope.enclose (outer inner : Scope) : Scope :=
  outer.map (fun source => { source with depth := source.depth + 1 }) ++ inner

/-- The scope of one table under its name, as a write or a query of one table has;
{lit}`hasRowid` is false for a {lit}`WITHOUT ROWID` table. -/
def Scope.single (name : Identifier) (columns : List CatalogColumn) (hasRowid : Bool := true) : Scope :=
  [{ name, columns, hasRowid }]

/-- Whether the position of the concatenated row is a cell of a trigger's row
({name}`ScopeSource.trigger`). -/
def Scope.triggerCell (scope : Scope) (position : Nat) : Bool :=
  scope.any fun source => source.trigger && source.offset ≤ position && position < source.offset + source.columns.length

/-- Whether the position of the concatenated row is a cell of an argument column of a
table-valued pragma ({name}`ScopeSource.arguments`). -/
def Scope.argumentCell (scope : Scope) (position : Nat) : Bool :=
  scope.any fun source => source.arguments.any (source.offset + · == position)

/-- The columns of all sources, in the order of the concatenated row. -/
def Scope.columns (scope : Scope) : List CatalogColumn := scope.flatMap (·.columns)

/-- The number of cells before the source at {lit}`index` of the query's own sources
({name}`Scope.inner`): its offset, or the number of cells of the whole scope for an index past
their end. -/
def Scope.cellsBefore (scope : Scope) (index : Nat) : Nat :=
  (scope.inner[index]?.map (·.offset)).getD scope.columns.length

/-- The columns of a source with their positions in the joined row that pass the filter
on their positions in the source. -/
def ScopeSource.placedColumns (source : ScopeSource) (keep : Nat → Bool) : List (Nat × CatalogColumn) :=
  ((source.columns.mapIdx fun index column => (index, column)).filter (keep ·.1)).map
    fun (index, column) => (source.offset + index, column)

/-- The columns that {lit}`*` reads, with their positions in the concatenated row: every
column of every source of the query's own sources ({name}`Scope.inner`), except a trigger's rows,
that is not merged ({name}`ScopeSource.merged`) or hidden ({name}`ScopeSource.hidden`). -/
def Scope.visible (scope : Scope) : List (Nat × CatalogColumn) :=
  (scope.inner.filter (!·.trigger)).flatMap fun source =>
    source.placedColumns fun index => !source.merged.contains index && !source.hidden.contains index

/-- The positions in the concatenated row of the columns that an unqualified name
names: the first column with the folded name in each source that has one and is no trigger's
row, unless that column is merged ({name}`ScopeSource.merged`). One position is a name; none is a missing
name; two or more are SQLite's {lit}`ambiguous column name`. -/
def Scope.matches (scope : Scope) (name : Identifier) : List Nat :=
  (scope.filter (!·.trigger)).flatMap fun source =>
    (((columnPosition source.columns name).filter (!source.merged.contains ·)).map (source.offset + ·)).toList

end Belay.Sqlite.Model
