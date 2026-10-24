import Belay.Sqlite.Model.Resolution.Scope

set_option doc.verso true

/-! The resolution of names over a scope (ADR 0012, amendment 2, "Names"; ADR 0018, D1 and
D5): unqualified names from the query's own sources outward, qualified names over the sources of
the qualifier, the rowid names, {lit}`source.*`, and the {lit}`NEW` and {lit}`OLD` rows of a
trigger, which only a qualified name sees. -/

namespace Belay.Sqlite.Model

/-- The resolution of an unqualified name over a scope: no column, two columns that no
join merges, or the position of the first column of the name with the positions whose
coalesce the name reads; one position is that column itself. -/
inductive NameResolution where
  /-- No source has a column of the name. -/
  | missing
  /-- Two sources have a column of the name that no join merged: SQLite's
  {lit}`ambiguous column name`. -/
  | ambiguous
  /-- The name: {lit}`first` is the position of its first column, and {lit}`reads` the
  positions of the columns that it reads, as their coalesce when there are several. -/
  | found (first : Nat) (reads : List Nat)
  deriving Repr, DecidableEq

/-- One step of {lit}`Scope.resolveName`: the next source after the result so far. A
column of the name in the first source with one gives it; a later one changes the result
only when the source's join merged it, by its {name}`MergeRule`, and makes the name
ambiguous otherwise. -/
def Scope.resolveStep (name : Identifier) (result : NameResolution) (source : ScopeSource) : NameResolution :=
  match columnPosition source.columns name, result with
  | none, result => result
  | some index, .missing => .found (source.offset + index) [source.offset + index]
  | some _, .ambiguous => .ambiguous
  | some index, .found first reads =>
    if source.merged.contains index then match source.mergeRule with
      | .keepLeft => .found first reads
      | .takeRight => .found first [source.offset + index]
      | .coalesce => .found first (reads ++ [source.offset + index])
    else .ambiguous

/-- Resolve an unqualified name over the sources of one depth from left to right
({name}`Scope.resolveStep`); a trigger's rows are not among them. -/
def Scope.resolveAt (scope : Scope) (name : Identifier) (depth : Nat) : NameResolution :=
  scope.foldl (fun result source =>
    if source.depth == depth && !source.trigger then Scope.resolveStep name result source else result) .missing

/-- One more than the largest depth of the scope's sources; 1 for an empty scope. -/
def Scope.depths (scope : Scope) : Nat :=
  scope.foldl (fun bound source => max bound (source.depth + 1)) 1

/-- Resolve an unqualified name as SQLite does (checked on native 3.51.0): in the query's own
sources first, then in those of each query around it, outward; the first depth with a column
of the name gives the result ({name}`Scope.resolveAt`). Over the sources of one depth, from left
to right ({name}`Scope.resolveStep`), the first source with a column of the folded name gives
that column; a later one changes the result only when its join merged the name; a later one
that did not merge it makes the name ambiguous. -/
def Scope.resolveName (scope : Scope) (name : Identifier) : NameResolution :=
  (((List.range scope.depths).map (scope.resolveAt name)).find? (· != .missing)).getD .missing

/-- Whether the source has the folded name. -/
def ScopeSource.named (source : ScopeSource) (name : Identifier) : Bool :=
  source.qualified && source.name.sameName name

/-- Whether a source of the query's own sources ({name}`Scope.inner`) that is no trigger's row
has the folded name. -/
def Scope.hasSource (scope : Scope) (name : Identifier) : Bool :=
  scope.inner.any fun source => source.named name && !source.trigger

/-- Whether a source with the folded name has a rowid ({name}`ScopeSource.hasRowid`). -/
def Scope.rowidSource (scope : Scope) (name : Identifier) : Bool :=
  scope.any fun source => source.named name && source.hasRowid

/-- Resolve the qualified name {lit}`source.column` as SQLite does (checked on native 3.51.0):
as an unqualified name ({name}`Scope.resolveName`) over only the sources with the folded
name {lit}`source`, so a column of two such sources that no join merged is SQLite's
{lit}`ambiguous column name`, and merged columns are visible. When a trigger's row has the name
(ADR 0018, D5), SQLite's {lit}`lookupName` tries it after the query's own sources and before
the queries around it: the query's own sources with the name first, then the trigger's row,
then the sources further out. Checked natively: in a trigger on {lit}`t(a, b)`,
{lit}`(SELECT new.a FROM log new)` reads {lit}`log.a`, and {lit}`(SELECT new.b FROM log new)`
reads the trigger's {lit}`NEW.b`, as {lit}`log` has no column {lit}`b`. -/
def Scope.resolveQualified (scope : Scope) (source column : Identifier) : NameResolution :=
  let named := scope.filter (·.named source)
  let real := named.filter (!·.trigger)
  match named.filter (·.trigger) with
  | [] => Scope.resolveName real column
  | rows => match Scope.resolveAt real column 0 with
    | .missing => match Scope.resolveName (rows.map fun row => { row with depth := 0, trigger := false }) column with
      | .missing => Scope.resolveName (real.filter (·.depth != 0)) column
      | .ambiguous => .ambiguous
      | .found first reads => .found first reads
    | .ambiguous => .ambiguous
    | .found first reads => .found first reads

/-- The columns of {lit}`source.*` with their positions in the concatenated row: every
column that is not hidden ({name}`ScopeSource.hidden`) of every source of the query's own
sources with the folded name, in order, merged columns included; none when no such source has
the name. -/
def Scope.starColumns? (scope : Scope) (name : Identifier) : Option (List (Nat × CatalogColumn)) :=
  if scope.hasSource name then
    some ((scope.inner.filter (·.named name)).flatMap fun source => source.placedColumns (!source.hidden.contains ·))
  else none


/-- The {lit}`NEW` and {lit}`OLD` rows of a trigger as the statements of its body see them (ADR
0018, D5): the columns of the trigger's table, and whether the event has {lit}`NEW` (INSERT and
UPDATE) and {lit}`OLD` (UPDATE and DELETE). -/
structure TriggerRow where
  /-- The columns of the trigger's table. -/
  columns : List CatalogColumn
  /-- Whether the event has {lit}`NEW`. -/
  new : Bool
  /-- Whether the event has {lit}`OLD`. -/
  old : Bool

/-- The sources of the rows that the event has, at the offset: {lit}`NEW`'s cells first when
the event has it, then {lit}`OLD`'s, each with a rowid, so that {lit}`new.rowid` is the
restriction of a rowid name. -/
def TriggerRow.scope (row : TriggerRow) (offset : Nat) : Scope :=
  let new : ScopeSource := { name := name! "new", columns := row.columns, offset, trigger := true }
  let old : ScopeSource :=
    { new with name := name! "old", offset := offset + if row.new then row.columns.length else 0 }
  (if row.new then [new] else []) ++ (if row.old then [old] else [])

/-- The number of cells of the rows: one for each column in each row that the event has. -/
def TriggerRow.width (row : TriggerRow) : Nat :=
  ((if row.new then 1 else 0) + (if row.old then 1 else 0)) * row.columns.length

end Belay.Sqlite.Model
