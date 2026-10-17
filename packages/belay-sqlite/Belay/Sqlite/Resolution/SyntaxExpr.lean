import Belay.Sqlite.Declarations
import Belay.Sqlite.Operators
import Belay.Sqlite.Resolution.ConflictAlgorithm

set_option doc.verso true

/-! Expressions and clauses as written, before name resolution; {lit}`Syntax` adds the
statements. Names are the decoded identifier text, with their case kept; omitted parts
are {lit}`none`. The frontend maps each parser production to one constructor without
reading the schema, and refuses syntax that has no constructor. Numeric literals keep their
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
  /-- A qualified column name {lit}`source.column`, with both names as written. The
  source is a table name or an alias. -/
  | qualified (source column : String)
  /-- Unary minus. -/
  | negate (operand : Expr)
  /-- Unary plus, which SQLite keeps as a no-op. -/
  | positive (operand : Expr)
  /-- The {lit}`=` or {lit}`==` comparison. -/
  | equals (left right : Expr)
  /-- A comparison other than {lit}`=`: {lit}`<>`, {lit}`<`, {lit}`<=`, {lit}`>`,
  {lit}`>=`, {lit}`IS` or {lit}`IS NOT`. -/
  | compare (operator : Comparison) (left right : Expr)
  /-- {lit}`AND`. -/
  | and (left right : Expr)
  /-- {lit}`OR`. -/
  | or (left right : Expr)
  /-- {lit}`NOT`. -/
  | not (operand : Expr)
  /-- {lit}`IS NULL`, or {lit}`IS NOT NULL` (also {lit}`NOTNULL`) when {lit}`negated`. -/
  | isNull (operand : Expr) (negated : Bool)
  /-- A function call with {lit}`*` as its argument, such as {lit}`COUNT(*)`, with the
  function name as written. -/
  | callStar (name : String)
  /-- A function call with one argument, such as {lit}`MIN(x)`, with the function
  name as written. Resolution folds the name and decides the function. -/
  | call (name : String) (operand : Expr)
  /-- An arithmetic operator, {lit}`+`, {lit}`-`, {lit}`*`, {lit}`/` or {lit}`%`, between
  two expressions. -/
  | arithmetic (operator : ArithmeticOperator) (left right : Expr)
  /-- {lit}`CAST(operand AS typeName)`, with the type name as written. -/
  | cast (operand : Expr) (typeName : String)
  /-- A function call with two or more arguments, with the function name as written:
  the first argument, then the last argument or, for three or more, the others as
  {lit}`more` nodes. {lit}`COALESCE(a, b, c)` is
  {lean}`Expr.callPair "COALESCE" (.identifier "a" false) (.more (.identifier "b" false) (.identifier "c" false))`.
  Resolution folds the name and decides the function. -/
  | callPair (name : String) (first rest : Expr)
  /-- The rest of an argument list of three or more arguments, the last operand of a
  {lit}`callPair`: one argument and the arguments after it. {lit}`f(a, b, c)` is
  {lit}`callPair f a (more b c)`, and {lit}`f(a, g(b, c))` stays
  {lit}`callPair f a (callPair g b c)`. -/
  | more (first rest : Expr)
  deriving Repr, DecidableEq

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
  /-- {lit}`PRIMARY KEY (columns) [ON CONFLICT algorithm]`. -/
  | primaryKey (columns : List String) (algorithm : Option ConflictAlgorithm := none)
  /-- {lit}`UNIQUE (columns) [ON CONFLICT algorithm]`. -/
  | unique (columns : List String) (algorithm : Option ConflictAlgorithm := none)
  deriving Repr, DecidableEq

/-- One result column of a {lit}`SELECT`: {lit}`*`, or an expression with an
optional {lit}`AS` alias and its source text as written, which SQLite uses as the
column name when there is no alias. -/
inductive ResultColumn where
  /-- {lit}`*`: every column of every source. -/
  | star
  /-- {lit}`source.*`: every column of the source with this name, as written. -/
  | sourceStar (source : String)
  /-- An expression, its alias, and its source text. -/
  | expression (value : Expr) (alias : Option String) (text : String)
  deriving Repr, DecidableEq

/-- A table in {lit}`FROM`, or a table-valued function such as {lit}`json_each(json)`: its
name and its optional alias, both as written, and the arguments of a function. Use
{lean}`(none : Option String)` for no alias, and {lean}`(none : Option (List Expr))` for a
table. -/
structure TableReference where
  /-- The table name, or the function name. -/
  table : String
  /-- The alias of {lit}`table AS alias` or {lit}`table alias`. -/
  alias : Option String
  /-- The arguments of a table-valued function in written order; none for a table. -/
  arguments : Option (List Expr) := none
  deriving Repr, DecidableEq

/-- One join of {lit}`FROM` after the first table: the keywords of its operator, the
joined table, its optional {lit}`ON` condition and its optional {lit}`USING` column
names. For {lit}`, t` the operator has no keywords and all optional parts are absent. -/
structure Join where
  /-- The keywords of the join operator before {lit}`JOIN`, as written, such as
  {lean}`["LEFT", "outer"]`; empty for {lit}`,` and a plain {lit}`JOIN`. Lean reads the
  kind of the join from them, so the frontend does not fold their case. -/
  operator : List String
  /-- The joined table. -/
  source : TableReference
  /-- The {lit}`ON` condition. -/
  condition : Option Expr
  /-- The {lit}`USING` column names, as written. -/
  usingColumns : Option (List String)
  deriving Repr, DecidableEq

/-- One {lit}`ORDER BY` term: an expression, and whether it is {lit}`DESC`. -/
structure OrderTerm where
  /-- The term as written. -/
  expression : Expr
  /-- Whether the term is {lit}`DESC`; {lean}`false` for {lit}`ASC` or no direction. -/
  descending : Bool
  deriving Repr, DecidableEq

end Belay.Sqlite.Syntax
