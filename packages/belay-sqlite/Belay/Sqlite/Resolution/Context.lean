import Belay.Sqlite.Resolution.Values

set_option doc.verso true

/-! The inputs of statement resolution, the result of one statement, and the
predicates on names and constraints that several statements share. -/

namespace Belay.Sqlite

/-- Whether the statements only describe a catalog, or are statements that the
execution semantics runs. A description, such as the schema text that SQLite keeps,
may contain the engine's statistics tables, constraints, defaults and indexes. The
execution semantics models CREATE TABLE with plain columns only and no CREATE
INDEX, so those are model restrictions for statements that it runs. -/
inductive Mode where
  /-- The statements describe a catalog; nothing runs them. -/
  | description
  /-- The execution semantics runs the statements. -/
  | execution
  deriving Repr, DecidableEq

/-- The inputs of resolution besides the catalog. -/
structure ResolveContext where
  /-- The execution profile, which supplies the limits. -/
  profile : Profile
  /-- Whether the statements describe a catalog or are run. -/
  mode : Mode

/-- The resolution of one statement: the resolved statement and the catalog after
it succeeds, or a model restriction. -/
abbrev StatementResolution := Except Restriction (Resolved.Statement × Catalog)

/-- Whether a DEFAULT expression is constant for SQLite: a literal, a signed
literal, a time keyword, or an identifier, which SQLite stores as text. A
comparison, logical operator, aggregate, arithmetic, {lit}`CAST` or a call
with two or more arguments counts as constant here, so that
resolution never predicts SQLite's error for it; the model restricts such
defaults instead ({lit}`Syntax.ColumnConstraint.modeledDefault`). -/
def constantDefault : Syntax.Expr → Bool
  | .null | .numeric _ | .string _ | .blob _ | .currentTime _ | .identifier .. => true
  | .negate operand | .positive operand => constantDefault operand
  | .equals .. | .qualified .. => false
  | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .callStar _ | .call .. => true
  | .arithmetic .. | .cast .. | .callPair .. => true

/-- Whether the constraint is PRIMARY KEY. -/
def Syntax.ColumnConstraint.isPrimaryKey : Syntax.ColumnConstraint → Bool
  | .primaryKey .. => true
  | .notNull _ | .unique _ | .default _ => false

/-- Whether the constraint is UNIQUE. -/
def Syntax.ColumnConstraint.isUnique : Syntax.ColumnConstraint → Bool
  | .unique _ => true
  | .notNull _ | .primaryKey .. | .default _ => false

/-- Whether the constraint is a DEFAULT that SQLite refuses as not constant. -/
def Syntax.ColumnConstraint.nonconstantDefault : Syntax.ColumnConstraint → Bool
  | .default value => !constantDefault value
  | .notNull _ | .primaryKey .. | .unique _ => false

/-- Whether the model describes the constraint's default: no default, or the
{lit}`CURRENT_TIMESTAMP` default, which the model keeps without evaluating it. Other
defaults are a model restriction until the execution semantics evaluates them. -/
def Syntax.ColumnConstraint.modeledDefault : Syntax.ColumnConstraint → Bool
  | .default (.currentTime keyword) => normalizeIdentifier keyword == "current_timestamp"
  | .default (.null) | .default (.numeric _) | .default (.string _) | .default (.blob _)
  | .default (.identifier ..) | .default (.negate _) | .default (.positive _)
  | .default (.equals ..) | .default (.compare ..) | .default (.and ..) | .default (.or ..)
  | .default (.not _) | .default (.isNull ..) | .default (.callStar _) | .default (.call ..)
  | .default (.arithmetic ..) | .default (.cast ..) | .default (.callPair ..) | .default (.qualified ..) => false
  | .notNull _ | .primaryKey .. | .unique _ => true

/-- A prepare error leaves the catalog unchanged. -/
def prepareError (catalog : Catalog) (error : PrepareError) : StatementResolution :=
  .ok (.prepareError error, catalog)

/-- A model restriction at a path of statement {lit}`index`. -/
def restrict (index : Nat) (path : List Nat) (kind : RestrictionKind) : StatementResolution :=
  .error { statement := index, path := path, kind := kind }

end Belay.Sqlite
