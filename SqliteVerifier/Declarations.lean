import Std

/-! Structural declarations retained by the ordinary-table backend. Constraint
truth is preserved through unchanged projections, not a fabricated SQL comparator. -/

namespace SqliteVerifier

/-- SQLite affinities for the admitted canonical declarations and explicit aliases. -/
inductive Affinity where
  | integer | real | text | blob | numeric
  deriving Repr, DecidableEq

/-- Canonical names are determined by affinity; aliases retain rowid-relevant spelling. -/
inductive DeclaredType where
  | canonical | bigInt | timestamp | boolean
  deriving Repr, DecidableEq

/-- Existing timestamp defaults are recorded but never evaluated by nullable ADD. -/
inductive ColumnDefault where
  | currentTimestamp
  deriving Repr, DecidableEq

/-- Existing declarations retain nullability and defaults; added columns are plain. -/
structure Column where
  name : String
  affinity : Affinity
  declaredType : DeclaredType := .canonical
  notNull : Bool := false
  defaultValue : Option ColumnDefault := none
  deriving Repr, DecidableEq

/-- Simple named indexes retain key order and uniqueness without expression semantics. -/
structure IndexDefinition where
  name : String
  columns : List String
  unique : Bool := false
  deriving Repr, DecidableEq

/-- Constraints and explicit indexes belong to their unchanged owning table. -/
structure TableProperties where
  primaryKey : List String := []
  uniqueKeys : List (List String) := []
  indexes : List IndexDefinition := []
  deriving Repr, DecidableEq

/-- Aliases have fixed SQLite affinity and never alias the physical rowid. -/
def declaredTypeMatches (column : Column) : Bool :=
  match column.declaredType with
  | .canonical => true
  | .bigInt => column.affinity == .integer
  | .timestamp | .boolean => column.affinity == .numeric

/-- New columns preserve the existing restricted, nullable, default-free semantics. -/
def Column.plain (column : Column) : Bool :=
  column.declaredType == .canonical && !column.notNull && column.defaultValue.isNone

end SqliteVerifier
