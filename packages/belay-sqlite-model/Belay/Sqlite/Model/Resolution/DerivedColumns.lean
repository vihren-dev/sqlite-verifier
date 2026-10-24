import Belay.Sqlite.Model.Resolution.CompoundNames

set_option doc.verso true

/-! Column metadata for query sources (ADR 0019, D5). SQLite's
{lit}`sqlite3SubqueryColumnTypes` uses every result expression, not only the first column
metadata that scalar and IN subqueries need. Affinity belongs to the expression; a literal
has no affinity, which differs from a catalog column declared without a type. -/

namespace Belay.Sqlite.Model

/-- SQLite's numeric and text possibility bits for a result expression. Blob and NULL
possibilities cannot change compound-column affinity and need no bit here. -/
abbrev ExpressionTypes := Bool × Bool

/-- Combine the numeric and text possibilities of two expressions. -/
def ExpressionTypes.union (left right : ExpressionTypes) : ExpressionTypes :=
  (left.1 || right.1, left.2 || right.2)

/-- Possibilities for a column, scalar subquery or CAST from its affinity. -/
def affinityTypes (affinity : Option Affinity) : ExpressionTypes :=
  if affinity.any numericAffinity then (true, false)
  else if affinity == some .text then (false, true) else (true, true)

/-- The affinity of a successfully resolved expression. Only a column, CAST, scalar subquery,
or COLLATE around one has affinity; unary plus removes it. Unknown names have none. -/
def Syntax.Expr.sourceAffinity (scope : Scope) (shapes : SubqueryShapes) : Syntax.Expr → Option Affinity
  | .identifier name _ => match scope.resolveName name with
    | .found _ reads => (scope.nameOperand reads).2
    | .missing | .ambiguous => none
  | .qualified source column => match scope.resolveQualified source column with
    | .found _ reads => (scope.nameOperand reads).2
    | .missing | .ambiguous => none
  | .cast _ typeName => some (affinityOf (some typeName))
  | .collate operand _ => operand.sourceAffinity scope shapes
  | .subquery index => (shapes.find index).bind (·.affinity)
  | .null | .numeric _ | .string _ | .blob _ | .parameter _ | .currentTime _ | .negate _ | .positive _
  | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .callStar _ | .call .. | .arithmetic ..
  | .exists _ | .inQuery .. | .inList .. | .between .. | .caseOf .. | .concatenate .. | .raise .. => none

mutual
/-- SQLite's numeric and text possibility bits ({lit}`sqlite3ExprDataType`) after names
resolve. CASE combines its result arms; unary plus retains type possibilities while removing
affinity. A missing double-quoted identifier has become a string, and TRUE/FALSE a number. -/
def Syntax.Expr.sourceTypes (scope : Scope) (shapes : SubqueryShapes) : Syntax.Expr → ExpressionTypes
  | .null | .blob _ => (false, false)
  | .string _ | .concatenate .. => (false, true)
  | .collate operand _ | .positive operand => operand.sourceTypes scope shapes
  | .parameter _ | .call .. | .callStar _ | .currentTime _ => (true, true)
  | value@(.identifier name quote) =>
    match scope.resolveName name with
    | .found .. => affinityTypes (value.sourceAffinity scope shapes)
    | .missing | .ambiguous => if quote == .double then (false, true) else (true, false)
  | value@(.qualified source column) =>
    match scope.resolveQualified source column with
    | .found _ reads => if reads.any scope.triggerCell then (true, false)
      else affinityTypes (value.sourceAffinity scope shapes)
    | .missing | .ambiguous => (true, true)
  | value@(.subquery _) | value@(.cast ..) => affinityTypes (value.sourceAffinity scope shapes)
  | .caseOf operands hasBase =>
    let types := Syntax.Expr.sourceTypesList scope shapes operands
    let arms := if hasBase then types.drop 1 else types
    arms.zipIdx.foldl (fun types (arm, index) =>
      if index % 2 == 1 || index + 1 == arms.length then
        ExpressionTypes.union types arm else types) (false, false)
  | .numeric _ | .negate _ | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .arithmetic ..
  | .exists _ | .inQuery .. | .inList .. | .between .. | .raise .. => (true, false)

/-- Type possibilities of each expression, used for the result arms of CASE. -/
def Syntax.Expr.sourceTypesList (scope : Scope) (shapes : SubqueryShapes) : List Syntax.Expr → List ExpressionTypes
  | [] => []
  | first :: rest => first.sourceTypes scope shapes :: Syntax.Expr.sourceTypesList scope shapes rest
end

/-- One result column used as a query-source column: name, expression affinity, collation
and SQLite's type possibilities. Use no affinity for a literal, and BINARY without COLLATE. -/
structure DerivedColumn where
  /-- The unique derived-table column name. -/
  name : String
  /-- The expression affinity, including none for a literal. -/
  affinity : Option Affinity
  /-- The expression's collation, BINARY when it has none. -/
  collation : Collation
  /-- The numeric and text possibility bits used to combine compound terms. -/
  types : ExpressionTypes
  deriving Repr, DecidableEq

/-- The metadata of successfully resolved result columns, with their original output names.
A merged star column uses the same operand affinity as a written name. -/
def resultSourceColumns (scope : Scope) (shapes : SubqueryShapes) (results : List Syntax.ResultColumn)
    (names : List String) : List DerivedColumn :=
  let metadata := results.flatMap fun
    | .star => scope.visible.map fun (position, column) =>
      let affinity := match scope.starOperand position column with
        | .ok operand => operand.2
        | .error _ => none
      (affinity, (scope.starCollation position column).getD .binary, affinityTypes affinity)
    | .sourceStar source => ((scope.starColumns? source).getD []).map fun (position, column) =>
      let affinity := match scope.starOperand position column with
        | .ok operand => operand.2
        | .error _ => none
      (affinity, (scope.starCollation position column).getD .binary, affinityTypes affinity)
    | .expression value _ _ =>
      [(value.sourceAffinity scope shapes, value.collationIn scope, value.sourceTypes scope shapes)]
  (names.zip metadata).map fun (name, affinity, collation, types) => { name, affinity, collation, types }

/-- Unique names for the columns of a query source. None means SQLite would choose a random
suffix for a duplicate, outside the deterministic name rules of {name}`derivedNames`. -/
def nameSourceColumns (scope : Scope) (results : List Syntax.ResultColumn)
    (columns : List DerivedColumn) : Option (List DerivedColumn) := do
  let names ← derivedNames scope results (columns.map (·.name))
  pure ((columns.zip names).map fun (column, name) => { column with name })

/-- The affinity of one compound-source column. SQLite takes the first expression with an
affinity, then changes TEXT to BLOB if another term may be numeric, or numeric affinity to
BLOB if another term may be text. No expression with affinity gives none. -/
def compoundSourceAffinity (columns : List DerivedColumn) : Option Affinity :=
  let selected := columns.findIdx? (·.affinity.isSome)
  selected.bind fun index => do
    let affinity ← columns[index]?.bind (·.affinity)
    let others := (columns.take index ++ columns.drop (index + 1)).foldl
      (fun types column => ExpressionTypes.union types column.types) (false, false)
    pure (if affinity == .text && others.1 || numericAffinity affinity && others.2 then .blob else affinity)

/-- Combine all output columns of compound terms. Names, collations and type possibilities
come from the left-most term; affinity follows {name}`compoundSourceAffinity` for each column. -/
def compoundSourceColumns (terms : List (List DerivedColumn)) : List DerivedColumn :=
  ((terms.head?).getD []).mapIdx fun index first =>
    { first with affinity := compoundSourceAffinity (terms.filterMap (·[index]?)) }

/-- The scope metadata of an indexed query source. An omitted alias gives unqualified
columns only; a source never has an implicit rowid. -/
def derivedScopeSource (index : Nat) (alias : Option Identifier) (columns : List DerivedColumn) : ScopeSource :=
  { name := alias.getD (name! ""), qualified := alias.isSome, queryIndex := some index, hasRowid := false,
    columns := columns.map fun column =>
      { name := Identifier.ofString column.name, declaredType := none, collation := column.collation },
    affinities := some (columns.map (·.affinity)) }

end Belay.Sqlite.Model
