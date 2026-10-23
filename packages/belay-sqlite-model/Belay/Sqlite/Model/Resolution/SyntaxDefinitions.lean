import Belay.Sqlite.Model.Resolution.SyntaxSubquery
import Belay.Sqlite.Model.Resolution.ForeignKeyAction
import Belay.Sqlite.Model.Resolution.ConflictAlgorithm

set_option doc.verso true

/-! Column definitions and constraints as written, before name resolution: the parts of
CREATE TABLE and ADD COLUMN that {lit}`Syntax` uses. -/

namespace Belay.Sqlite.Model.Syntax

/-- A DEFAULT expression and its source spelling. The expression determines the
value; the text preserves metadata such as {lit}`X'00ff'` versus {lit}`x'00FF'`.
For example, {lean}`({ expression := .numeric "7", sourceText := "7" } : DefaultExpression)`
is the default written as {lit}`7`. -/
structure DefaultExpression where
  /-- The expression evaluated when a column value is omitted. -/
  expression : Expr
  /-- The expression text reported by SQLite, excluding DEFAULT and its outer parentheses. -/
  sourceText : String
  deriving BEq

/-- Print a default as a constructor application so generated nested catalog terms
keep valid Lean indentation when an expression spans several lines. -/
instance : Repr DefaultExpression where
  reprPrec value prec := Repr.addAppParen
    ("Belay.Sqlite.Model.Syntax.DefaultExpression.mk " ++ reprArg value.expression ++ " " ++ reprArg value.sourceText) prec

/-- A column constraint as written. For example, {lit}`PRIMARY KEY DESC` is
{lean}`ColumnConstraint.primaryKey true`. -/
inductive ColumnConstraint where
  /-- {lit}`NOT NULL [ON CONFLICT algorithm]`; {lean}`(none : Option ConflictAlgorithm)`
  without the clause. -/
  | notNull (algorithm : Option ConflictAlgorithm := none)
  /-- {lit}`PRIMARY KEY [ASC | DESC] [ON CONFLICT algorithm]`; the flag is true for
  {lit}`DESC`. -/
  | primaryKey (descending : Bool) (algorithm : Option ConflictAlgorithm := none)
  /-- {lit}`UNIQUE [ON CONFLICT algorithm]`. -/
  | unique (algorithm : Option ConflictAlgorithm := none)
  /-- {lit}`DEFAULT` with its expression and its source text, excluding DEFAULT
  and any outer parentheses belonging to the DEFAULT production. -/
  | default (value : Expr) (sourceText : String)
  /-- {lit}`COLLATE name`, with the collation name as written (ADR 0014, slice 3). -/
  | collate (name : Identifier)
  /-- {lit}`CHECK (condition)` with the label that SQLite reports when it fails: the name of
  the {lit}`CONSTRAINT name` in effect, else the source text between the parentheses
  without outer white space, dequoted when it starts with a quote (ADR 0014, slice 4). -/
  | check (condition : Expr) (label : String)
  /-- {lit}`REFERENCES table [(columns)]` with its {lit}`ON DELETE` and {lit}`ON UPDATE`
  actions; the other clauses do not show in {lit}`PRAGMA foreign_key_list` (ADR 0014,
  slice 4). -/
  | references (table : Identifier) (columns : List Identifier) (onDelete onUpdate : ForeignKeyAction)
  /-- {lit}`[GENERATED ALWAYS] AS (expression) [kind]` with the kind word as written, none
  without one; resolution reads {lit}`VIRTUAL` and {lit}`STORED` with ASCII case ignored
  (ADR 0014, slice 5). -/
  | generated (expression : Expr) (kind : Option Identifier)
  /-- A deferral clause, which sets whether the last foreign key of the table so far is
  deferred, as SQLite's {lit}`sqlite3DeferForeignKey` does: true only for
  {lit}`DEFERRABLE INITIALLY DEFERRED` (ADR 0018, D4). -/
  | deferral (deferred : Bool)
  deriving Repr, BEq

/-- One column of CREATE TABLE or ADD COLUMN. Use {lean}`(none : Option String)`
for a column without a declared type. -/
structure ColumnDefinition where
  /-- The column name as written. -/
  name : Identifier
  /-- The declared type text as written, for example {lit}`VARCHAR(10)`. -/
  declaredType : Option String
  /-- The column constraints in written order. -/
  constraints : List ColumnConstraint
  deriving Repr, BEq

/-- A table constraint of CREATE TABLE, with column names as written. -/
inductive TableConstraint where
  /-- {lit}`PRIMARY KEY (columns) [ON CONFLICT algorithm]`. -/
  | primaryKey (columns : List Identifier) (algorithm : Option ConflictAlgorithm := none)
  /-- {lit}`UNIQUE (columns) [ON CONFLICT algorithm]`. -/
  | unique (columns : List Identifier) (algorithm : Option ConflictAlgorithm := none)
  /-- {lit}`CHECK (condition)` with its label, as for {name}`ColumnConstraint.check`. SQLite
  ignores an {lit}`ON CONFLICT` clause of a table CHECK (ADR 0014, slice 4). -/
  | check (condition : Expr) (label : String)
  /-- {lit}`FOREIGN KEY (columns) REFERENCES table [(referenced)]` with its actions, as for
  {name}`ColumnConstraint.references`; {lit}`referenced` is empty without a column list. -/
  | foreignKey (columns : List Identifier) (table : Identifier) (referenced : List Identifier)
      (onDelete onUpdate : ForeignKeyAction)
  /-- The deferral clause of the {lit}`FOREIGN KEY` before it, as for
  {name}`ColumnConstraint.deferral`. -/
  | deferral (deferred : Bool)
  deriving Repr, BEq

end Belay.Sqlite.Model.Syntax
