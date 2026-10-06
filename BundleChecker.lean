import GateCore
import StructuralCodec
import Export.Parse

/-! ADR 0003 data path: check an exported proof bundle without compiling candidate source.

A bundle is one file: a JSON header line, then a lean4export NDJSON export. The
header names the trusted-library modules the export references but omits. The
checker imports those only from the sysroot and verifier library, imports the
verifier-compiled starting schema and contract, constructs the generated SQL
declarations from the frontend's structural record (`generatedDeclarations`),
requires every exported declaration that repeats a trusted one to match it, replays
the rest in the kernel, and applies the same target, audit and exit codes as the
`.olean` gate. -/

open Lean ProofChecker

/-- lean4export drops metadata and sets `let` nondep flags to false; apply the same. -/
partial def normalize (e : Expr) : Expr :=
  e.replace fun sub => match sub with
    | .mdata _ inner => some (normalize inner)
    | .letE n t v b _ => some (.letE n (normalize t) (normalize v) (normalize b) false)
    | _ => none

/-- Normalize every expression of a complete declaration record, keeping all other fields. -/
def normalizeInfo : ConstantInfo → ConstantInfo
  | .defnInfo v => .defnInfo { v with type := normalize v.type, value := normalize v.value }
  | .thmInfo v => .thmInfo { v with type := normalize v.type, value := normalize v.value }
  | .opaqueInfo v => .opaqueInfo { v with type := normalize v.type, value := normalize v.value }
  | .axiomInfo v => .axiomInfo { v with type := normalize v.type }
  | .quotInfo v => .quotInfo { v with type := normalize v.type }
  | .inductInfo v => .inductInfo { v with type := normalize v.type }
  | .ctorInfo v => .ctorInfo { v with type := normalize v.type }
  | .recInfo v =>
    let rules := v.rules.map (fun (r : RecursorRule) => { r with rhs := normalize r.rhs })
    .recInfo { v with type := normalize v.type, rules := rules }

/-- Declarations the checker constructs itself instead of compiling `SqlInputs.lean`. -/
def generatedNames : List Name := [`Generated.nextSchema, `Generated.script, `Generated.profile]

/-- A closed, safe definition with the hints Lean would assign to an ordinary `def`. -/
def definition (env : Environment) (name : Name) (type value : Expr) : ConstantInfo :=
  .defnInfo { name, levelParams := [], type, value, safety := .safe, all := [name],
              hints := .regular (getMaxHeight env value + 1) }

/-- Build `Generated.nextSchema`, `script` and `profile` from the frontend's record.

The record's starting schema must equal the compiled `Generated.startSchema`, so the
constructed declarations describe the same request as the contract's inputs. -/
def generatedDeclarations (env : Environment) (inputs : SqliteVerifier.GeneratedInputs) :
    IO (Std.HashMap Name ConstantInfo) := do
  let start ← closedConstant env `Generated.startSchema
  unless ← kernelResult (Kernel.isDefEq env {} start (toExpr inputs.schema)) do
    throw <| IO.userError "generated inputs do not match the compiled starting schema"
  let schema := mkConst `SqliteVerifier.Schema
  let script := mkApp (mkConst ``List [levelZero]) (mkConst `SqliteVerifier.Statement)
  return Std.HashMap.ofList [
    (`Generated.nextSchema, definition env `Generated.nextSchema schema (toExpr inputs.nextSchema)),
    (`Generated.script, definition env `Generated.script script (toExpr inputs.script)),
    (`Generated.profile, definition env `Generated.profile
      (mkConst `SqliteVerifier.ExecutionProfile) (toExpr inputs.profile))]

/-- Same type and definitionally equal value: elaborated and constructed literals differ
structurally (numerals, `nextSchema := startSchema`) but must denote the same data. -/
def sameDefinition (env : Environment) (a b : ConstantInfo) : IO Bool := do
  match a, b with
  | .defnInfo x, .defnInfo y =>
    if x.levelParams != y.levelParams || x.safety != y.safety then return false
    unless ← kernelResult (Kernel.isDefEq env {} x.type y.type) do return false
    kernelResult (Kernel.isDefEq env {} x.value y.value)
  | _, _ => return false

/-- Split exported declarations into fresh ones, rejecting any changed protected record.

Replay always uses the verifier's own declarations; this comparison only rejects a
bundle that was prepared against different inputs. -/
def exportedAdditions (trusted : Environment) (exported : Export.ExportedEnv) :
    IO (Std.HashMap Name ConstantInfo) := do
  let mut fresh := {}
  for (name, info) in exported.constMap.toList do
    if let some pinned := trusted.toKernelEnv.find? name then
      let same ← if info == pinned || normalizeInfo info == normalizeInfo pinned then pure true
        else if generatedNames.contains name then sameDefinition trusted info pinned
        else pure false
      unless same do
        throw <| IO.userError s!"modified protected declaration: {name}"
    else
      fresh := fresh.insert name info
  return fresh

/-- Read and decode the frontend's structural record. -/
def readGenerated (path : System.FilePath) : IO SqliteVerifier.GeneratedInputs := do
  let json ← IO.ofExcept (Json.parse (← IO.FS.readFile path))
  IO.ofExcept (SqliteVerifier.decodeGeneratedInputs json)

/-- Read the version-1 header: `{"bundle": 1, "trusted_imports": ["Mod", ...]}`. -/
def readHeader (line : String) : IO (Array Name) := do
  let json ← IO.ofExcept (Json.parse line)
  match json.getObjValAs? Nat "bundle" with
  | .ok 1 => pure ()
  | _ => throw <| IO.userError "unsupported bundle format; expected version 1"
  let modules ← IO.ofExcept (json.getObjValAs? (Array String) "trusted_imports")
  return modules.map String.toName

/-- Import the trusted base and the compiled starting schema, returning the import state. -/
def schemaEnvironment (library trusted : System.FilePath) (external : NameSet) :
    IO (Environment × ImportState) := do
  let sysroot ← requireDirectories [library, trusted]
  let builtin ← getBuiltinSearchPath sysroot
  -- Trusted modules resolve only from the sysroot and verifier library.
  searchPathRef.set (builtin ++ [library])
  let (base, state) ← importData (baseModules external) default
  searchPathRef.set (builtin ++ [library, trusted])
  let (inputs, state) ← importData #[`SchemaInputs] state
  return (Environment.ofKernelEnv (← base.toKernelEnv.replay (← additions base inputs)), state)

/-- Check one bundle against the pinned library, the compiled contract and the
generated inputs constructed from the frontend's record. -/
def checkBundle (library trusted bundle generated : System.FilePath) : IO UInt32 := do
  let stream := IO.FS.Stream.ofHandle (← IO.FS.Handle.mk bundle .read)
  let claimed ← readHeader (← stream.getLine)
  let contract ← trustedImports [trusted] [`SchemaInputs, `Requirements, `Interpretation]
  let (schemaEnv, state) ← schemaEnvironment library trusted (claimed.foldl (·.insert ·) contract)
  let inputEnv := Environment.ofKernelEnv
    (← schemaEnv.toKernelEnv.replay (← generatedDeclarations schemaEnv (← readGenerated generated)))
  let (approved, _) ← importData #[`Requirements, `Interpretation] state
  let trustedEnv := Environment.ofKernelEnv (← inputEnv.toKernelEnv.replay (← additions inputEnv approved))
  let exported ← Export.parseStream stream
  let checked := Environment.ofKernelEnv (← trustedEnv.toKernelEnv.replay (← exportedAdditions trustedEnv exported))
  checkTarget checked (exported.constMap.contains `Proofs.migrationCorrect)

/-- Test mode (ADR 0003 assumption A5): the constructed declarations must agree with
`SqlInputs.olean` compiled from today's emitter for the same request. -/
def checkParity (library trusted generated : System.FilePath) : IO UInt32 := do
  let contract ← trustedImports [trusted] [`SchemaInputs, `SqlInputs]
  let (schemaEnv, state) ← schemaEnvironment library trusted contract
  let constructed ← generatedDeclarations schemaEnv (← readGenerated generated)
  let (compiled, _) ← importData #[`SqlInputs] state
  for name in generatedNames do
    let some built := constructed[name]? | throw <| IO.userError s!"not constructed: {name}"
    let some emitted := compiled.toKernelEnv.find? name
      | throw <| IO.userError s!"not emitted: {name}"
    unless built.type == emitted.type do
      throw <| IO.userError s!"type differs from the emitter: {name}"
    unless ← sameDefinition compiled built emitted do
      throw <| IO.userError s!"value differs from the emitter: {name}"
  return 0

/-- Exit 0 for a checked proof, 2 for a checked refutation, 1 for anything else. -/
def main (arguments : List String) : IO UInt32 := do
  try
    match arguments with
    | ["--parity", library, trusted, generated] => checkParity library trusted generated
    | [library, trusted, bundle, generated] => checkBundle library trusted bundle generated
    | _ => throw (IO.userError "usage: migration-bundle-checker LIBRARY TRUSTED BUNDLE GENERATED_JSON")
  catch error =>
    IO.eprintln s!"bundle checker rejected: {error}"
    return 1
