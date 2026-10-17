import Belay.Sqlite.Resolution.Sources

set_option doc.verso true

/-! Resolution of a {lit}`SELECT` (ADR 0012, slice 1, and amendment 2 for joins). The
steps follow SQLite's resolver: the tables of {lit}`FROM` ({lit}`Sources`), the result
columns, {lit}`WHERE`, the {lit}`ON` conditions, {lit}`GROUP BY`, {lit}`ORDER BY`, then
{lit}`LIMIT` and {lit}`OFFSET`. The paths of a restriction use the child positions of
{lit}`Syntax.Statement.select`: 0 the columns, 1 the first table, 2 the joins, 3 the
filter, 4 the grouping terms, 5 the ordering terms, 6 the limit and 7 the offset. -/

namespace Belay.Sqlite

/-- The integer of a numeric value, if it is one. -/
def NumericValue.integer? : NumericValue → Option Int
  | .integer value => some value
  | .real | .hexTooBig => none

/-- The value of an integer literal, possibly negated; {lean}`(none : Option Int)`
for any other expression. -/
def integerLiteral : Syntax.Expr → Option Int
  | .numeric text => (numericValue text false).integer?
  | .negate operand => match operand with
    | .numeric text => (numericValue text true).integer?
    | .null | .string _ | .blob _ | .currentTime _ | .identifier .. | .negate _ | .positive _ | .equals ..
    | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .callStar _ | .call .. | .arithmetic .. | .cast ..
    | .callPair .. | .more .. | .qualified .. => none
  | .null | .string _ | .blob _ | .currentTime _ | .identifier .. | .positive _ | .equals .. | .compare ..
  | .and .. | .or .. | .not _ | .isNull .. | .callStar _ | .call .. | .arithmetic .. | .cast .. | .callPair ..
  | .more .. | .qualified .. => none

/-- One resolved result column with its names: {lit}`*` gives every column of every
source that is not merged ({name}`Scope.visible`) under its defined name, a merged pair as
its unqualified name ({name}`Scope.starOperand`), {lit}`x.*` every column of source
{lit}`x` ({name}`sourceStarColumns`); an aggregate is a whole result column; any other expression
is a scalar. A name is the {lit}`AS` alias, else the defined name of a referenced column
({name}`definedName`), else the source text as written. -/
def resolveResultColumn (dqs : Bool) (scope : Scope) (column : Nat) :
    Syntax.ResultColumn → Except ValueIssue (List (Resolved.Output × String))
  | .star => if scope.isEmpty then .error (.prepare .noTablesSpecified) else
      .ok (scope.visible.map fun (position, defined) => (.scalar (scope.starOperand position defined).1, defined.name))
  | .sourceStar source => (sourceStarColumns scope source).map fun columns =>
      columns.map fun (expression, name) => (.scalar expression, name)
  | .expression value alias text => do
    let named := fun (output : Resolved.Output) (defined : Option String) => [(output, alias.getD (defined.getD text))]
    match value with
    | .callStar name =>
      if normalizeIdentifier name == "count" then .ok (named (.aggregate .countRows) none)
      else throw ((callIssue name).under [0, column, 0])
    | .call name operand => match aggregateNamed name with
      | some aggregate =>
        let (resolved, _) ← (resolveOperand dqs scope true operand).mapError (·.under [0, column, 0, 1])
        .ok (named (.aggregate (aggregate resolved)) none)
      | none =>
        if (jsonFunctionNamed name).isSome then do
          let (resolved, _) ← (resolveOperand dqs scope false value).mapError (·.under [0, column, 0])
          .ok (named (.scalar resolved) none)
        else throw ((callIssue name).under [0, column, 0])
    | .null | .numeric _ | .string _ | .blob _ | .currentTime _ | .identifier .. | .qualified .. | .negate _
    | .positive _ | .equals .. | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .arithmetic .. | .cast ..
    | .callPair .. | .more .. =>
      let (resolved, _) ← (resolveOperand dqs scope false value).mapError (·.under [0, column, 0])
      .ok (named (.scalar resolved) (definedName scope value))

/-- The index of the first result column whose alias has the folded name. -/
def aliasIndex (names : List (Option String)) (name : String) : Option Nat :=
  names.findIdx? fun alias => alias.any (normalizeIdentifier · == normalizeIdentifier name)

/-- Whether a result column of an aggregate query is admitted by the model: an
aggregate, or a scalar that is one of the grouping terms. SQLite also admits other
scalars ("bare columns", whose row it chooses); that is a model restriction. -/
def groupedOutput (terms : List Resolved.Expr) : Resolved.Output → Bool
  | .aggregate _ => true
  | .scalar expression => terms.contains expression

/-- The result column that an {lit}`ORDER BY` or {lit}`GROUP BY` term names: an integer
{lit}`k` from 1 to the number of columns names column {lit}`k - 1`; an identifier
names the first column with that alias. {lit}`some (.error ())` is an integer out of
range; {lean}`(none : Option (Except Unit Nat))` is any other term. -/
def namedResult (names : List (Option String)) : Syntax.Expr → Option (Except Unit Nat)
  | .identifier name _ => (aliasIndex names name).map .ok
  | term@.null | term@(.numeric _) | term@(.string _) | term@(.blob _) | term@(.currentTime _)
  | term@(.negate _) | term@(.positive _) | term@(.equals ..) | term@(.compare ..) | term@(.and ..)
  | term@(.or ..) | term@(.not _) | term@(.isNull ..) | term@(.callStar _) | term@(.call ..)
  | term@(.arithmetic ..) | term@(.cast ..) | term@(.callPair ..) | term@(.more ..) | term@(.qualified ..) =>
    (integerLiteral term).map fun (number : Int) =>
      if 1 ≤ number ∧ number ≤ (names.length : Int) then .ok (number.toNat - 1) else .error ()

/-- Resolve a {lit}`LIMIT` or {lit}`OFFSET` expression: an integer literal, or none. -/
def windowValue (path : List Nat) : Option Syntax.Expr → Except ValueIssue (Option Int)
  | none => .ok none
  | some term => match integerLiteral term with
    | some value => .ok (some value)
    | none => .error (.restriction path .windowValue)

/-- Whether a query is a model restriction because SQLite may skip a failing group: it
has {lit}`GROUP BY`, a {lit}`LIMIT` or {lit}`OFFSET`, and a result column that can fail
({name}`Resolved.Output.canFail`). SQLite finalizes the groups in an order that the
model does not describe and stops at the window, so it may never compute a group
whose {lit}`SUM` overflows. -/
def windowSkipsFailure (groupBy : List Syntax.Expr) (limit offset : Option Syntax.Expr)
    (outputs : List Resolved.Output) : Bool :=
  !groupBy.isEmpty && (limit.isSome || offset.isSome) && outputs.any Resolved.Output.canFail

/-- Resolve a {lit}`SELECT`; see the module documentation for the steps. -/
def resolveSelect (context : ResolveContext) (catalog : Catalog) (index : Nat)
    (results : List Syntax.ResultColumn) (source : Option Syntax.TableReference) (joins : List Syntax.Join)
    (filter : Option Syntax.Expr) (groupBy : List Syntax.Expr) (orderBy : List Syntax.OrderTerm)
    (limit offset : Option Syntax.Expr) : StatementResolution :=
  let dqs := context.profile.dqsDml
  let resolved : Except ValueIssue Resolved.Query := do
    let (first, tables, scope) ← resolveTables catalog source joins
    let outputs := (← resolveAll (resolveResultColumn dqs scope) results).flatten
    let aliases := results.flatMap fun
      | .star => scope.visible.map fun _ => none
      | .sourceStar name => ((scope.source? name).map (·.2.map fun _ => none)).getD []
      | .expression _ alias _ => [alias]
    let condition ← match filter with
      | none => pure none
      | some term =>
        if namesAlias scope (aliases.filterMap id) term then throw (aliasInExpression.under [3])
        else some <$> condition [3] (resolveOperand dqs scope true term)
    let conditions ← resolveAll (fun item (_, term) => resolveJoinCondition dqs scope item term) tables
    let aggregate := !groupBy.isEmpty || outputs.any fun (output, _) => match output with
      | .aggregate _ => true
      | .scalar _ => false
    let grouped := fun (column : Nat) => match outputs[column]? with
      | some (.scalar expression, _) => .ok expression
      | some (.aggregate _, _) | none => .error (.prepare .aggregateInGroupBy)
    let terms ← resolveAll (fun item term => match term with
      | .identifier name _ => match scope.resolveName name, aliasIndex aliases name with
        | .found _ reads, _ => .ok (scope.nameOperand reads).1
        | .missing, some column => grouped column
        | .missing, none | .ambiguous, _ =>
          (resolveOperand dqs scope true term).map (·.1) |>.mapError (·.under [4, item])
      | .callStar name | .call name _ =>
        .error (if aggregateCall term then .prepare .aggregateInGroupBy else (callIssue name).under [4, item])
      | .numeric _ | .negate _ => match namedResult aliases term with
        | some (.ok column) => grouped column
        | some (.error ()) => .error (.prepare (.groupByOutOfRange (item + 1) outputs.length))
        | none => .error (.restriction [4, item] .groupByTerm)
      | .qualified .. => (resolveOperand dqs scope true term).map (·.1) |>.mapError (·.under [4, item])
      | .null | .string _ | .blob _ | .currentTime _ | .positive _ | .equals .. | .compare .. | .and .. | .or ..
      | .not _ | .isNull .. | .arithmetic .. | .cast .. | .callPair .. | .more .. =>
        .error (.restriction [4, item] .groupByTerm)) groupBy
    if aggregate && !outputs.all (groupedOutput terms ·.1) then
      throw (.restriction [0] .bareColumn)
    let order ← resolveAll (fun item (term : Syntax.OrderTerm) => match namedResult aliases term.expression with
      | some (.ok column) => .ok (Resolved.SortKey.output column, term.descending)
      | some (.error ()) => .error (.prepare (.orderByOutOfRange (item + 1) outputs.length))
      | none =>
        if aggregate then .error (.restriction [5, item] .aggregateOrderBy)
        else if namesAlias scope (aliases.filterMap id) term.expression then
          .error (aliasInExpression.under [5, item, 0])
        else (resolveOperand dqs scope false term.expression).map (fun (e, _) => (.expression e, term.descending))
          |>.mapError (·.under [5, item, 0])) orderBy
    let limitValue ← windowValue [6] limit
    let offsetValue ← windowValue [7] offset
    if offsetValue.any (· < 0) then throw (.restriction [7] .negativeOffset)
    if windowSkipsFailure groupBy limit offset (outputs.map (·.1)) then
      throw (.restriction [6] .windowedGroupSum)
    let resolvedJoins := (joins.zip ((tables.map Prod.fst).zip conditions)).map fun (join, table, on) =>
      ({ kind := join.resolvedKind, table, condition := on } : Resolved.Join)
    return { table := first, joins := resolvedJoins, filter := condition, aggregate, groupBy := terms,
             columns := outputs.map (·.1), names := outputs.map (·.2), orderBy := order,
             offset := (offsetValue.getD 0).toNat,
             limit := limitValue.bind fun value => if value < 0 then none else some value.toNat }
  match resolved with
  | .ok query => .ok (.query query, catalog)
  | .error issue => issueResolution catalog index [] issue

/-- For every successful resolution of a {lit}`SELECT`, the catalog is unchanged.
Proof sketch: every branch of the resolver returns the input catalog. -/
theorem resolveSelect_same (context : ResolveContext) (catalog after : Catalog) (index : Nat)
    (results : List Syntax.ResultColumn) (source : Option Syntax.TableReference) (joins : List Syntax.Join)
    (filter : Option Syntax.Expr) (groupBy : List Syntax.Expr) (orderBy : List Syntax.OrderTerm)
    (limit offset : Option Syntax.Expr) (statement : Resolved.Statement)
    (ok : resolveSelect context catalog index results source joins filter groupBy orderBy limit offset =
      .ok (statement, after)) :
    after = catalog := by
  unfold resolveSelect at ok
  simp only [prepareError, issueResolution] at ok
  repeat' split at ok
  all_goals first | (cases ok; rfl) | (cases ok)

end Belay.Sqlite
