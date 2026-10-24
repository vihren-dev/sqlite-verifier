import Belay.Sqlite.Model.ModelLaws
import Belay.Sqlite.Model.Resolution.QueryExprs

set_option doc.verso true

/-! The positions that name resolution reads (ADR 0022, D3, slice 4). Over a scope whose sources
all end below a width, an unqualified or qualified name reads only positions below the width.
{lit}`ResolveReadsBelow` uses this to show that the CHECK constraints and the index terms that
resolution makes read only the columns of their table. -/

namespace Belay.Sqlite.Model

/-- For the given scope and width: every source of the scope ends at or below the width, that is
its offset plus its number of columns is at most the width. The scope of one table
({name}`Scope.single`) has this property for the width of the table. An empty scope has it for
every width. -/
def Scope.Bounded (scope : Scope) (width : Nat) : Prop :=
  ∀ source ∈ scope, source.offset + source.columns.length ≤ width

/-- For the given width and name resolution: a name that is found reads only positions below the
width. A missing or ambiguous name requires nothing. -/
def NameResolution.Below (width : Nat) : NameResolution → Prop
  | .found _ reads => ∀ position ∈ reads, position < width
  | .missing | .ambiguous => True

/-- For every list of columns, name and found position, the position is below the number of
columns ({name}`columnPosition`). Proof sketch: it is the position of {name}`findPosition`, which
is below the length ({name}`findPosition_lt`). -/
theorem columnPosition_lt {columns : List CatalogColumn} {name : Identifier} {index : Nat}
    (found : columnPosition columns name = some index) : index < columns.length := by
  obtain ⟨⟨position, column⟩, search, same⟩ := Option.map_eq_some_iff.mp found
  cases same
  exact findPosition_lt search

/-- For every width, name, resolution so far and source that ends below the width: if the
resolution so far reads below the width, so does the resolution after the source
({name}`Scope.resolveStep`). Proof sketch: a column of the source is at its offset plus a
position below its number of columns, and every other case keeps or appends to the positions. -/
theorem Scope.resolveStep_below {width : Nat} (name : Identifier) {result : NameResolution} {source : ScopeSource}
    (ends : source.offset + source.columns.length ≤ width) (below : result.Below width) :
    (Scope.resolveStep name result source).Below width := by
  unfold Scope.resolveStep
  split
  · exact below
  · rename_i index found
    have := columnPosition_lt found
    simp only [NameResolution.Below, List.mem_singleton, forall_eq]
    omega
  · trivial
  · rename_i index first reads found
    have := columnPosition_lt found
    split
    · split
      · exact below
      · simp only [NameResolution.Below, List.mem_singleton, forall_eq]
        omega
      · simp only [NameResolution.Below, List.mem_append, List.mem_singleton] at below ⊢
        rintro position (member | equal)
        · exact below position member
        · omega
    · trivial

/-- For every scope that ends below a width, name and depth, the resolution of the name at the
depth reads below the width ({name}`Scope.resolveAt`). Proof sketch: induction over the sources of
the fold, with {name}`Scope.resolveStep_below` for each source that is used. -/
theorem Scope.resolveAt_below {width : Nat} {scope : Scope} (bounded : scope.Bounded width) (name : Identifier)
    (depth : Nat) : (scope.resolveAt name depth).Below width := by
  have step : ∀ (sources : Scope) (state : NameResolution), state.Below width → (∀ source ∈ sources,
      source.offset + source.columns.length ≤ width) →
      (sources.foldl (fun result source =>
        if source.depth == depth && !source.trigger then Scope.resolveStep name result source else result) state).Below width := by
    intro sources
    induction sources with
    | nil => intro state holds _; exact holds
    | cons source rest ih =>
      intro state holds ends
      apply ih _ _ fun other member => ends other (List.mem_cons_of_mem _ member)
      dsimp only
      split
      · exact Scope.resolveStep_below name (ends source List.mem_cons_self) holds
      · exact holds
  exact step scope .missing trivial bounded

/-- For every scope that ends below a width and every name, the resolution of the name reads below
the width ({name}`Scope.resolveName`). Proof sketch: the result is the resolution of one depth
({name}`Scope.resolveAt_below`), or missing. -/
theorem Scope.resolveName_below {width : Nat} {scope : Scope} (bounded : scope.Bounded width) (name : Identifier) :
    (scope.resolveName name).Below width := by
  unfold Scope.resolveName
  cases found : ((List.range scope.depths).map (scope.resolveAt name)).find? (· != .missing) with
  | none => trivial
  | some result =>
    have member := List.mem_of_find?_eq_some found
    simp only [List.mem_map] at member
    obtain ⟨depth, _, same⟩ := member
    simpa [← same] using Scope.resolveAt_below bounded name depth

/-- For every scope that ends below a width, the scope without some sources ends below it. Proof
sketch: a source of the filtered scope is a source of the original scope. -/
theorem Scope.bounded_filter {width : Nat} {scope : Scope} (bounded : scope.Bounded width) (keep : ScopeSource → Bool) :
    Scope.Bounded (scope.filter keep) width :=
  fun source member => bounded source (List.mem_filter.mp member).1

/-- For every scope that ends below a width, source name and column name, the resolution of the
qualified name reads below the width ({name}`Scope.resolveQualified`). Proof sketch: each branch
resolves a name over a sub-scope ({name}`Scope.bounded_filter`) or over the trigger rows with
changed depth, which keep their offsets and columns, with {name}`Scope.resolveName_below`. -/
theorem Scope.resolveQualified_below {width : Nat} {scope : Scope} (bounded : scope.Bounded width)
    (source column : Identifier) : (scope.resolveQualified source column).Below width := by
  have named := Scope.bounded_filter bounded (·.named source)
  have real := Scope.bounded_filter named (!·.trigger)
  unfold Scope.resolveQualified
  dsimp only
  have atBelow := Scope.resolveAt_below real column 0
  have deeper := Scope.resolveName_below (Scope.bounded_filter real fun source => source.depth != 0) column
  cases hrows : List.filter (·.trigger) (List.filter (·.named source) scope) with
  | nil => exact Scope.resolveName_below real column
  | cons first rest =>
    have rowsBound : Scope.Bounded ((first :: rest).map fun row => ({ row with depth := 0, trigger := false } : ScopeSource)) width := by
      intro found member
      obtain ⟨row, inRows, same⟩ := List.mem_map.mp member
      subst same
      rw [← hrows] at inRows
      exact named row (List.mem_filter.mp inRows).1
    have rowsName := Scope.resolveName_below rowsBound column
    cases hat : Scope.resolveAt (List.filter (!·.trigger) (List.filter (·.named source) scope)) column 0 with
    | missing =>
      dsimp only
      cases inner : Scope.resolveName ((first :: rest).map fun row => { row with depth := 0, trigger := false }) column with
      | missing => exact deeper
      | ambiguous => trivial
      | found first reads => rw [inner] at rowsName; exact rowsName
    | ambiguous => trivial
    | found first reads => rw [hat] at atBelow; exact atBelow

end Belay.Sqlite.Model
