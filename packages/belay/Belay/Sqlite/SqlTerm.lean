import Lean.Elab.Term
import Belay.Sqlite.Model.Codec.Resolution
import Belay.Sqlite.Translation
import Belay.Sqlite.Script
import Belay.Sqlite.SqlLiteral
import Belay.Sqlite.SqlParameters

set_option doc.verso true

/-! {lit}`sql r"..."` (ADR 0017, D3 and D4): a {lit}`Script` of the statements of the SQL text,
which the translation reads while the file elaborates. SQL that SQLite's grammar rejects, and a
form that the translation refuses, is an elaboration error at its position in the text. The
term does not resolve the statements; each one resolves when it runs. A parameter {lit}`$x` is
the Lean variable {lit}`x`, and every other parameter makes the term a function of
{lit}`Value` arguments ({lit}`Belay/Sqlite/SqlParameters.lean`). -/

namespace Belay.Sqlite

open Lean Elab Term Meta

/-- {lit}`sql "SQL"`: the script of the statements of the SQL text. For example,
{lit}`sql r"BEGIN; COMMIT"` is a script of two statements. A parameter {lit}`$x` gets the value of
the Lean variable {lit}`x`, coerced to {lit}`Value`. Each other parameter, {lit}`?`, {lit}`?NNN`,
{lit}`:name`, {lit}`@name` or {lit}`#name`, is an explicit argument of type {lit}`Value`, in the
order of the first appearance: {lit}`sql r"UPDATE t SET a = :a WHERE id = :id"` has the type
{lit}`(a id : Value) → Script`. A name gives the argument of that name, and {lit}`?5` gives
{lit}`p5`. A file that imports the surface reads {lit}`sql` as this keyword, so a name
{lit}`sql` there is written {lit}`«sql»`. -/
syntax:max (name := sqlTerm) "sql " str : term

/-- The statements of the SQL text with their ranges and parameter tokens, translated with the
grammar of the default release, or the refusal. -/
def translateText (text : String) :
    IO (Except Translation.Refusal (Array Translation.ParameterizedStatement)) := do
  let grammar ← IO.ofExcept ((selectGrammar (← loadedMetadata) Release.default).mapError IO.userError)
  Translation.translate grammar text.toUTF8

/-- The statements of the literal's SQL text, or an error at the position where SQLite's grammar
rejects the text or the translation refuses a form. -/
def literalStatements (literal : Syntax) : TermElabM (Array Translation.ParameterizedStatement) := do
  let some text := literal.isStrLit? | throwUnsupportedSyntax
  match ← (translateText text : IO _) with
  | .ok items => return items
  | .error refusal =>
    throwErrorAt (textRange literal text refusal.start (max refusal.stop (refusal.start + 1))) refusal.message

/-- The term of the script of the statements, each with no values: the script that
{lit}`Script.withValues` binds in the term of a text with parameters ({lit}`scriptTerm`). -/
def scriptExpr (items : Array Translation.ParameterizedStatement) : Expr :=
  mkApp (mkConst ``Script.mk) (toExpr (items.toList.map fun item => (item.statement.value, ([] : List Belay.Sqlite.Model.Value))))

/-- The type {lit}`Value` of the model, which every parameter's value has. -/
def valueType : Expr := Lean.mkConst ``Belay.Sqlite.Model.Value

/-- The value of a parameter {lit}`$x`: the Lean variable {lit}`x`, elaborated where the script is
and outside the arguments of the script's function, and coerced to {lit}`Value`. An error is at
the parameter in the SQL text ({name}`textRange`): a name that does not resolve, and a type
without a coercion to {lit}`Value`. -/
def variableValue (literal : Syntax) (text : String) (name : String) (parameter : Translation.Parameter) :
    TermElabM Expr := do
  let ref := textRange literal text parameter.start parameter.stop
  let value ← try
      let value ← withoutErrToSorry <| elabTerm (mkIdentFrom ref (Name.mkSimple name)) none
      synthesizeSyntheticMVarsNoPostponing
      instantiateMVars value
    catch error =>
      throwErrorAt ref m!"the parameter {parameter.text} is the Lean variable {name}, and Lean cannot elaborate it: {error.toMessageData}\nDeclare a variable {name}, or write :{name} to make {name} an argument of the script"
  let type ← instantiateMVars (← inferType value)
  try withRef ref do
      let coerced ← ensureHasType valueType value
      synthesizeSyntheticMVarsNoPostponing
      instantiateMVars coerced
  catch _ =>
    throwErrorAt ref m!"the parameter {parameter.text} is the Lean variable {name} of type {type}, which has no coercion to Value; give {name} the type Value, String or Int64, or convert it to a Value"

/-- The term of the script of the statements: {name}`scriptExpr` for a text without parameters;
otherwise the function of the arguments ({name}`planParameters`) whose value is
{lit}`Script.withValues` of {name}`scriptExpr` with one list for each statement, with the value of
each number from 1 to the statement's largest one: an argument, the value of a variable
({name}`variableValue`), or NULL for a number without a parameter. An error of the plan is at its
parameter in the SQL text. -/
def scriptTerm (literal : Syntax) (text : String) (items : Array Translation.ParameterizedStatement) :
    TermElabM Expr := do
  let plan ← match planParameters (items.toList.map (·.parameters)) with
    | .ok plan => pure plan
    | .error diagnostic => throwErrorAt (textRange literal text diagnostic.start diagnostic.stop) diagnostic.message
  let script := scriptExpr items
  if plan.slots.all (·.isEmpty) then return script
  let variables ← plan.variables.mapM fun (name, parameter) => do
    return (ParameterSource.variable name, ← variableValue literal text name parameter)
  withLocalDeclsDND (plan.arguments.map fun name => (Name.mkSimple name, valueType)).toArray fun arguments => do
    let sources := variables ++ (plan.arguments.map ParameterSource.argument).zip arguments.toList
    let null := Lean.mkConst ``Belay.Sqlite.Model.Value.null
    -- Each source of a slot is in `sources`: the plan adds a variable or an argument for each one.
    let slotValue : Slot → Expr
      | .null => null
      | .source source => (sources.lookup source).getD null
    let lists ← mkListLit (mkApp (Lean.mkConst ``List [Level.zero]) valueType)
      (← plan.slots.mapM fun slots => mkListLit valueType (slots.map slotValue))
    mkLambdaFVars arguments (mkApp2 (Lean.mkConst ``Script.withValues) script lists)

/-- Elaborate {lit}`sql "SQL"` to the script of its statements ({name}`scriptTerm`). -/
@[term_elab sqlTerm]
def elabSql : TermElab := fun term _ => do
  let literal := term[1]
  let some text := literal.isStrLit? | throwUnsupportedSyntax
  scriptTerm literal text (← literalStatements literal)

end Belay.Sqlite
