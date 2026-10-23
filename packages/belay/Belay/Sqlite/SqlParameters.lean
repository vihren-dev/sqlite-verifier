import Belay.Sqlite.Translation
import Belay.Sqlite.SqlDiagnostics

set_option doc.verso true

/-! The meaning of the parameters of {lit}`sql r"..."` (ADR 0017, S3; ADR 0019, D1), without
elaboration: a parameter {lit}`$x` is the Lean variable {lit}`x`, and every other parameter is
an argument of type {lit}`Value` of the function that the term gives. This module decides the
arguments, the variables and the value of each parameter number of each statement, or the error
at the parameter that makes the text wrong. {lit}`Belay/Sqlite/SqlTerm.lean` builds the term. -/

namespace Belay.Sqlite

open Translation

/-- What gives the value of one parameter: a Lean variable that {lit}`$x` names, or an argument
of the script's function. -/
inductive ParameterSource where
  /-- The Lean variable of the name, written {lit}`$name`. -/
  | variable (name : String)
  /-- The argument of the name: {lit}`:name`, {lit}`@name` and {lit}`#name` give the name
  without the sign, and {lit}`?` and {lit}`?NNN` give {lit}`p` and the number. -/
  | argument (name : String)
  deriving BEq, Repr, Inhabited

/-- The Lean name of the source: the variable's name or the argument's name. -/
def ParameterSource.name : ParameterSource → String
  | .variable name | .argument name => name

/-- The value of one parameter number of a statement: the source of the parameter that has the
number, or NULL when no parameter of the statement has it, as SQLite binds it. -/
inductive Slot where
  /-- No parameter has the number. -/
  | null
  /-- The parameter of the source has the number. -/
  | source (source : ParameterSource)
  deriving BEq, Repr, Inhabited

/-- The parameters of a script: the argument names in the order of their first appearance, the
variables with the first parameter that names each one, and for each statement the slot of
each number from 1 to its largest number. -/
structure ParameterPlan where
  /-- The names of the arguments of the function, in the order of their first appearance. -/
  arguments : List String := []
  /-- The names of the Lean variables, each with the first {lit}`$` parameter that names it. -/
  variables : List (String × Parameter) := []
  /-- The slots of each statement, item {lit}`n - 1` for number {lit}`n`. -/
  slots : List (List Slot) := []
  deriving Inhabited

/-- Whether the text after the sign {lit}`$` is a Lean identifier of one part, such as
{lit}`x` or {lit}`total'`. For example, {assert}`isLeanIdentifier "a::b" = false`. -/
def isLeanIdentifier (name : String) : Bool :=
  match name.toList with
  | first :: rest => Lean.isIdFirst first && rest.all Lean.isIdRest
  | [] => false

/-- The source of one parameter token, or the error at a {lit}`$` name that is not a Lean
identifier. -/
def parameterSource (parameter : Parameter) : Except Diagnostic ParameterSource :=
  let at_ (message : String) : Diagnostic := { start := parameter.start, stop := parameter.stop, message }
  match parameter.text.toList with
  | '$' :: name =>
    if isLeanIdentifier (String.ofList name) then .ok (.variable (String.ofList name))
    else .error (at_ s!"the parameter {parameter.text} must name a Lean variable, and its name is not a Lean identifier; write a Lean identifier such as $x, or write :name to make an argument")
  | '?' :: _ => .ok (.argument s!"p{parameter.number}")
  | _ :: name => .ok (.argument (String.ofList name))
  | [] => .ok (.argument s!"p{parameter.number}")

/-- What makes two parameter tokens one parameter, as SQLite reads them: the number for
{lit}`?` and {lit}`?NNN`, so that {lit}`?` and {lit}`?1` of number 1 are one parameter, and the
text with its sign for a name, so that {lit}`:id` and {lit}`@id` are two parameters. For
example, the key of {lit}`?` of number 3 is {lit}`?3`. -/
def parameterKey (parameter : Parameter) : String :=
  if parameter.text.startsWith "?" then s!"?{parameter.number}" else parameter.text

/-- The plan so far while the parameters are read in text order: the plan, and the first
parameter that gives each Lean name with its source. -/
structure PlanState where
  /-- The plan so far; the slots are those of the statements read so far. -/
  plan : ParameterPlan := {}
  /-- Each Lean name with the first parameter that gives it. -/
  names : List (String × Parameter) := []

/-- Add one parameter of a statement to the state, with the sources of the earlier parameters of
the statement by number, or the error at the parameter: two parameters
({name}`parameterKey`) that give one Lean name, such as {lit}`:id` and {lit}`@id`, and two
parameters of one statement with one number, such as {lit}`$x` and {lit}`?1`. -/
def addParameter (state : PlanState) (numbers : List (Nat × Parameter × ParameterSource))
    (parameter : Parameter) : Except Diagnostic (PlanState × List (Nat × Parameter × ParameterSource)) := do
  let source ← parameterSource parameter
  let at_ (message : String) : Diagnostic := { start := parameter.start, stop := parameter.stop, message }
  let state ← match state.names.lookup source.name with
    | some first =>
      if parameterKey first == parameterKey parameter then pure state
      else throw (at_ s!"the parameters {first.text} and {parameter.text} both give the Lean name {source.name}; rename one of them")
    | none =>
      let plan := match source with
        | .variable name => { state.plan with variables := state.plan.variables ++ [(name, parameter)] }
        | .argument name => { state.plan with arguments := state.plan.arguments ++ [name] }
      pure { plan, names := state.names ++ [(source.name, parameter)] }
  match numbers.lookup parameter.number with
  | some (first, earlier) =>
    if parameterKey first == parameterKey parameter then return (state, numbers)
    throw (at_ s!"SQLite gives the parameters {first.text} and {parameter.text} of this statement one number, {parameter.number}, and a number holds one value, but they give two Lean names, {earlier.name} and {source.name}; write one parameter for both, or give ?{parameter.number} another number")
  | none => return (state, numbers ++ [(parameter.number, parameter, source)])

/-- The slots of a statement from the sources of its numbers: one slot for each number from 1
to the largest one. -/
def statementSlots (numbers : List (Nat × Parameter × ParameterSource)) : List Slot :=
  let largest := numbers.foldl (fun largest item => max largest item.1) 0
  (List.range largest).map fun index => match numbers.lookup (index + 1) with
    | some (_, source) => .source source
    | none => .null

/-- The plan of the parameters of the statements, each with its parameter tokens in text order,
or the error of the first parameter in text order that makes the text wrong. For example, in
{lit}`SELECT :a, ?3`, the arguments are {lit}`a` and {lit}`p3`, and the slots are {lit}`a`,
NULL and {lit}`p3`. -/
def planParameters (statements : List (List Parameter)) : Except Diagnostic ParameterPlan := do
  let mut state : PlanState := {}
  let mut slots : List (List Slot) := []
  for parameters in statements do
    let mut numbers : List (Nat × Parameter × ParameterSource) := []
    for parameter in parameters do
      (state, numbers) ← addParameter state numbers parameter
    slots := slots ++ [statementSlots numbers]
  return { state.plan with slots }

end Belay.Sqlite
