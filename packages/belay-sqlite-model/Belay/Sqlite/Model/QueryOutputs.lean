import Belay.Sqlite.Model.Output

set_option doc.verso true

/-! What the output of a query says about its rows, for every result that SQLite may give: which
statements only read, and whether an output has rows or has none. The surface states queries as
propositions with them ({lit}`Holds`, {lit}`Empty` and {lit}`Fails`). -/

namespace Belay.Sqlite.Model

/-- Whether the statement only reads: a {lit}`SELECT`, or a pragma that only reads
({name}`Syntax.Pragma.readsOnly`). -/
def Syntax.Statement.readsOnly : Syntax.Statement → Bool
  | .select .. => true
  | .pragma form => form.readsOnly
  | .createTable .. | .createIndex .. | .addColumn .. | .dropTable ..
  | .dropIndex .. | .begin | .commit | .rollback | .insert .. | .update .. | .delete ..
  | .createTrigger .. | .dropTrigger .. => false

/-- Whether the output says that each result that SQLite may give has a row: rows that are not
empty, or at least one result, of which none is empty. -/
def Output.hasRows : Output → Bool
  | .rows found => !found.isEmpty
  | .oneOf results => !results.isEmpty && results.all (!·.isEmpty)
  | .done _ | .error _ | .unmodeled _ => false

/-- Whether the output says that each result that SQLite may give has no row: rows that are
empty, or at least one result, of which each is empty. -/
def Output.hasNoRows : Output → Bool
  | .rows found => found.isEmpty
  | .oneOf results => !results.isEmpty && results.all (·.isEmpty)
  | .done _ | .error _ | .unmodeled _ => false

/-- For each output, {name}`Output.hasRows` and {name}`Output.hasNoRows` are not both true. Proof
sketch: by cases on the output; for {name}`Output.oneOf`, the first result is empty and not
empty. -/
theorem Output.hasRows_not_hasNoRows (output : Output) (rows : output.hasRows = true) :
    output.hasNoRows = false := by
  cases output with
  | rows found => simp_all [Output.hasRows, Output.hasNoRows]
  | oneOf results =>
    cases results with
    | nil => simp [Output.hasRows] at rows
    | cons first rest => simp_all [Output.hasRows, Output.hasNoRows]
  | done _ | error _ | unmodeled _ => simp [Output.hasRows] at rows

/-- For each output: if {name}`Output.hasRows` is true, then {name}`Output.isError` is false.
Proof sketch: by cases on the output. -/
theorem Output.hasRows_not_isError (output : Output) (rows : output.hasRows = true) : output.isError = false := by
  cases output <;> simp_all [Output.hasRows, Output.isError]

/-- For each output: if {name}`Output.hasNoRows` is true, then {name}`Output.isError` is false.
Proof sketch: by cases on the output. -/
theorem Output.hasNoRows_not_isError (output : Output) (empty : output.hasNoRows = true) : output.isError = false := by
  cases output <;> simp_all [Output.hasNoRows, Output.isError]

end Belay.Sqlite.Model
