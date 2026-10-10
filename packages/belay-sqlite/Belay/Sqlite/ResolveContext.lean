import Belay.Sqlite.ResolveValues

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

/-- Whether the folded name starts with {lit}`sqlite_`, which SQLite reserves. -/
def reservedName (name : String) : Bool := (normalizeIdentifier name).startsWith "sqlite_"

/-- Whether a column name is one of SQLite's rowid names, which the model keeps
for the physical rowid. -/
def rowidName (name : String) : Bool :=
  ["rowid", "_rowid_", "oid"].contains (normalizeIdentifier name)

/-- Whether a DEFAULT expression is constant for SQLite: a literal, a signed
literal, a time keyword, or an identifier, which SQLite stores as text. -/
def constantDefault : Syntax.Expr → Bool
  | .null | .numeric _ | .string _ | .blob _ | .currentTime _ | .identifier .. => true
  | .negate operand | .positive operand => constantDefault operand
  | .equals .. => false

/-- Whether the constraint is PRIMARY KEY. -/
def Syntax.ColumnConstraint.isPrimaryKey : Syntax.ColumnConstraint → Bool
  | .primaryKey _ => true
  | .notNull | .unique | .default _ => false

/-- Whether the constraint is UNIQUE. -/
def Syntax.ColumnConstraint.isUnique : Syntax.ColumnConstraint → Bool
  | .unique => true
  | .notNull | .primaryKey _ | .default _ => false

/-- Whether the constraint is a DEFAULT that SQLite refuses as not constant. -/
def Syntax.ColumnConstraint.nonconstantDefault : Syntax.ColumnConstraint → Bool
  | .default value => !constantDefault value
  | .notNull | .primaryKey _ | .unique => false

/-- Whether the model describes the constraint's default: no default, or the
{lit}`CURRENT_TIMESTAMP` default, which the model keeps without evaluating it. Other
defaults are a model restriction until the execution semantics evaluates them. -/
def Syntax.ColumnConstraint.modeledDefault : Syntax.ColumnConstraint → Bool
  | .default (.currentTime keyword) => normalizeIdentifier keyword == "current_timestamp"
  | .default (.null) | .default (.numeric _) | .default (.string _) | .default (.blob _)
  | .default (.identifier ..) | .default (.negate _) | .default (.positive _)
  | .default (.equals ..) => false
  | .notNull | .primaryKey _ | .unique => true

/-- A prepare error leaves the catalog unchanged. -/
def prepareError (catalog : Catalog) (error : PrepareError) : StatementResolution :=
  .ok (.prepareError error, catalog)

/-- A model restriction at a path of statement {lit}`index`. -/
def restrict (index : Nat) (path : List Nat) (reason : String) : StatementResolution :=
  .error { statement := index, path := path, reason := reason }

end Belay.Sqlite
