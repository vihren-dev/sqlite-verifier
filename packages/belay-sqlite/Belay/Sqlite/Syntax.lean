set_option doc.verso true

/-! Statements and expressions as written, before name resolution. Names are the
decoded identifier text, with their case kept; omitted parts are {lit}`none`. The
frontend maps each parser production to one constructor without reading the
schema, and refuses syntax that has no constructor. Numeric literals keep their
token text, because SQLite's conversion rules are not lexical. -/

namespace Belay.Sqlite.Syntax

/-- An expression as written. For example, the literal {lit}`-5` is
{lean}`Expr.negate (.numeric "5")`. -/
inductive Expr where
  /-- The {lit}`NULL` keyword. -/
  | null
  /-- A numeric literal's token text, for example {lean}`Expr.numeric "1_000"`. -/
  | numeric (text : String)
  /-- A string literal's decoded UTF-8 bytes, without the quotes. -/
  | string (bytes : List UInt8)
  /-- A blob literal's decoded bytes, for example {lit}`X'00FF'` gives two bytes. -/
  | blob (bytes : List UInt8)
  /-- The keywords {lit}`CURRENT_TIME`, {lit}`CURRENT_DATE` or
  {lit}`CURRENT_TIMESTAMP`, as written. -/
  | currentTime (keyword : String)
  /-- An identifier. {name}`Expr.identifier` records whether it was written in
  double quotes, which decides SQLite's double-quoted-string fallback. -/
  | identifier (name : String) (doubleQuoted : Bool)
  /-- Unary minus. -/
  | negate (operand : Expr)
  /-- Unary plus, which SQLite keeps as a no-op. -/
  | positive (operand : Expr)
  /-- The {lit}`=` or {lit}`==` comparison. -/
  | equals (left right : Expr)
  deriving Repr, DecidableEq

/-- A column constraint as written. For example, {lit}`PRIMARY KEY DESC` is
{lean}`ColumnConstraint.primaryKey true`. -/
inductive ColumnConstraint where
  /-- {lit}`NOT NULL`. -/
  | notNull
  /-- {lit}`PRIMARY KEY`; the flag is true for {lit}`DESC`. -/
  | primaryKey (descending : Bool)
  /-- {lit}`UNIQUE`. -/
  | unique
  /-- {lit}`DEFAULT` with its expression. -/
  | default (value : Expr)
  deriving Repr, DecidableEq

/-- One column of CREATE TABLE or ADD COLUMN. Use {lean}`(none : Option String)`
for a column without a declared type. -/
structure ColumnDefinition where
  /-- The column name as written. -/
  name : String
  /-- The declared type text as written, for example {lit}`VARCHAR(10)`. -/
  declaredType : Option String
  /-- The column constraints in written order. -/
  constraints : List ColumnConstraint
  deriving Repr, DecidableEq

/-- A table constraint of CREATE TABLE, with column names as written. -/
inductive TableConstraint where
  /-- {lit}`PRIMARY KEY (columns)`. -/
  | primaryKey (columns : List String)
  /-- {lit}`UNIQUE (columns)`. -/
  | unique (columns : List String)
  deriving Repr, DecidableEq

/-- One statement as written. For example, {lit}`COMMIT` is
{lean}`Statement.commit`. -/
inductive Statement where
  /-- {lit}`CREATE TABLE name (columns, constraints)`. -/
  | createTable (name : String) (columns : List ColumnDefinition)
      (constraints : List TableConstraint)
  /-- {lit}`CREATE [UNIQUE] INDEX name ON table (columns)`. -/
  | createIndex (name : String) (unique : Bool) (table : String) (columns : List String)
  /-- {lit}`ALTER TABLE table ADD COLUMN column`. -/
  | addColumn (table : String) (column : ColumnDefinition)
  /-- {lit}`BEGIN`. -/
  | begin
  /-- {lit}`COMMIT` or {lit}`END`. -/
  | commit
  /-- {lit}`ROLLBACK`. -/
  | rollback
  /-- {lit}`INSERT INTO table [(columns)] VALUES rows`; a missing column list is
  {lean}`(none : Option (List String))`. -/
  | insert (table : String) (columns : Option (List String)) (rows : List (List Expr))
  /-- {lit}`UPDATE table SET assignments [WHERE filter]`. -/
  | update (table : String) (assignments : List (String × Expr)) (filter : Option Expr)
  deriving Repr, DecidableEq

end Belay.Sqlite.Syntax
