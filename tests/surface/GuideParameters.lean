import Belay

/-! A fixture of `tests/surface_parameters_test.py`: the examples of the user guide's section
"Parameters" that need no program, and the parameters of `sql r"..."`
(`Belay/Sqlite/SqlParameters.lean`, `Belay/Sqlite/SqlTerm.lean`, the coercions of
`Belay/Sqlite/Values.lean`): `$x` is the Lean variable `x` coerced to `Value`, every other
parameter is an argument of type `Value`, each statement binds the arguments at the numbers that
SQLite gives the parameters, and the term is `Script.withValues` of the script without values.
The file fails to elaborate when an example does not hold. -/

open Belay.Sqlite

/-- The guide's database of "Parameters": table `invoices` with two invoices, and table
`customers` with one customer. -/
def shop : Database := db! r"
  CREATE TABLE invoices (id INTEGER PRIMARY KEY, customer TEXT NOT NULL, amount INTEGER NOT NULL);
  INSERT INTO invoices VALUES (1, 'acme', 10), (2, 'zeta', 0);
  CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
  INSERT INTO customers VALUES (1, 'acme');"

-- The guide's examples.
/-- The guide's `nameOf`: the name of the customer with the id, which `$id` reads from the Lean
variable `id`. -/
def nameOf (id : Int64) : Script := sql r"SELECT name FROM customers WHERE id = $id"

/-- The guide's `setAmount`: a function of the arguments `amount` and `id`, in the order of their
first appearance. -/
def setAmount := sql r"UPDATE invoices SET amount = :amount WHERE id = :id"

/-- info: setAmount (amount id : Value) : Script -/
#guard_msgs in
#check setAmount

/-- info: [done 1] -/
#guard_msgs in
#eval (shop.run (setAmount (id := 1) (amount := 15))).outputs

/-- info: [rows [["acme"]]] -/
#guard_msgs in
#eval (shop.run (nameOf 1)).outputs

-- `$x` of each coerced type: `Value`, `String` and `Int64`, the INTEGER of `Int64.toInt`.
example (x : Value) : (sql r"SELECT $x").statements.map (·.2) = [[x]] := rfl
example (x : String) : (sql r"SELECT $x").statements.map (·.2) = [[(x : Value)]] := rfl
example (x : Int64) : (sql r"SELECT $x").statements.map (·.2) = [[.integer x.toInt]] := rfl
example : (nameOf (-3)).statements.map (·.2) = [[.integer (-3)]] := by decide +kernel
example : ((-3 : Int64) : Value) = .integer (-3) := by decide +kernel

-- The numbers that SQLite gives `?, ?5, ?, :a, @b, $x, :a, ?1` are 1, 5, 6, 7, 8, 9, 7, 1. The
-- arguments are `p1`, `p5`, `p6`, `a` and `b`, in the order of their first appearance, and `$x`
-- is the variable `x`.
example (x p1 p5 p6 a b : Value) :
    (sql r"SELECT ?, ?5, ?, :a, @b, $x, :a, ?1" p1 p5 p6 a b).statements.map (·.2) =
      [[p1, .null, .null, .null, p5, p6, a, b, x]] := rfl
example (x : Value) : sql r"SELECT ?, ?5, ?, :a, @b, $x, :a, ?1" (b := 5) (a := 4) (p6 := 3) (p5 := 2) (p1 := 1) =
    sql r"SELECT ?, ?5, ?, :a, @b, $x, :a, ?1" 1 2 3 4 5 := rfl

-- `?5` alone: items 1 to 4 are NULL, as SQLite binds them.
example (p5 : Value) : (sql r"SELECT ?5" p5).statements.map (·.2) = [[.null, .null, .null, .null, p5]] := rfl

-- One name in two statements gives one argument, which each statement binds at its own number.
-- A statement without parameters binds no values.
example (id : Value) : (sql r"SELECT :id; SELECT 1; SELECT ?, :id" id .null).statements.map (·.2) =
    [[id], [], [.null, id]] := rfl

-- The order of the arguments is the order of the first appearance in the text, over all
-- statements; `#name` gives an argument as `:name` does.
example (a b c : Value) : (sql r"SELECT @b; SELECT #c, :a, @b" b c a).statements.map (·.2) =
    [[b], [c, a, b]] := rfl

-- The term is `Script.withValues` of the script without values, so `Script.withValues` binds
-- other values after the notation, in place of those of the notation.
example (a : Value) : sql r"SELECT :a" a = (sql r"SELECT :a" .null).withValues [[a]] := rfl
example (a : Value) : ((sql r"SELECT :a, ?2" a .null).withValues [[.integer 1, .integer 2]]).statements.map (·.2) =
    [[.integer 1, .integer 2]] := rfl

-- `sql! db r"..."` gives the term of `sql r"..."`, with its arguments and variables.
example (x : Int64) : sql! shop r"SELECT name FROM customers WHERE id = $x OR id = :id" =
    sql r"SELECT name FROM customers WHERE id = $x OR id = :id" := rfl

-- A script with `$n` and `:m` is a function of `m` whose values read the variable `n`.
example (n : Value) : (sql r"SELECT $n, :m" .null).statements.map (·.2) = [[n, .null]] := rfl

-- A run reads the values: the guide's call changes the amount of invoice 1.
example : (shop.run (setAmount (id := 1) (amount := 15) ++ sql r"SELECT amount FROM invoices WHERE id = 1")).outputs =
    [.done 1, .rows [[.integer 15]]] := by decide +kernel

-- `Holds`, `Empty` and `Fails` take a query with a `$x` value or an argument: the check that the
-- script is a query (`check_query`) does not depend on the values.
/-- The query holds on the database when table `invoices` has `n` rows; `n` is a Lean variable. -/
def countIs (n : Value) (db : Database) : Prop :=
  Holds (sql r"SELECT 1 WHERE (SELECT count(*) FROM invoices) = $n") db
example : countIs 2 shop := by unfold countIs; decide +kernel
example : ¬ countIs 3 shop := by unfold countIs; decide +kernel
example : Empty (sql r"SELECT 1 FROM invoices WHERE id = :id" 3) shop := by decide +kernel
