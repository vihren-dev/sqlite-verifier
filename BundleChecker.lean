import GateCore
import Export.Parse

/-! ADR 0003 data path: check an exported proof bundle without compiling candidate source.

A bundle is one file: a JSON header line, then a lean4export NDJSON export. The
header names the trusted-library modules the export references but omits. The
checker imports those only from the sysroot and verifier library, imports the
verifier-compiled contract and generated inputs, requires every exported
declaration that repeats a trusted one to match it, replays the rest in the
kernel, and applies the same target, audit and exit codes as the `.olean` gate. -/

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

/-- Split exported declarations into fresh ones, rejecting any changed protected record. -/
def exportedAdditions (trusted : Environment) (exported : Export.ExportedEnv) :
    IO (Std.HashMap Name ConstantInfo) := do
  let mut fresh := {}
  for (name, info) in exported.constMap.toList do
    if let some pinned := trusted.toKernelEnv.find? name then
      unless info == pinned || normalizeInfo info == normalizeInfo pinned do
        throw <| IO.userError s!"modified protected declaration: {name}"
    else
      fresh := fresh.insert name info
  return fresh

/-- Read the version-1 header: `{"bundle": 1, "trusted_imports": ["Mod", ...]}`. -/
def readHeader (line : String) : IO (Array Name) := do
  let json ← IO.ofExcept (Json.parse line)
  match json.getObjValAs? Nat "bundle" with
  | .ok 1 => pure ()
  | _ => throw <| IO.userError "unsupported bundle format; expected version 1"
  let modules ← IO.ofExcept (json.getObjValAs? (Array String) "trusted_imports")
  return modules.map String.toName

/-- Check one bundle against the pinned library and the verifier-compiled contract. -/
def checkBundle (library trusted bundle : System.FilePath) : IO UInt32 := do
  let sysroot ← requireDirectories [library, trusted]
  let builtin ← getBuiltinSearchPath sysroot
  let stream := IO.FS.Stream.ofHandle (← IO.FS.Handle.mk bundle .read)
  let claimed ← readHeader (← stream.getLine)
  let contract ← trustedImports [trusted] [`SchemaInputs, `SqlInputs, `Requirements, `Interpretation]
  let external := claimed.foldl (·.insert ·) contract
  -- Trusted modules resolve only from the sysroot and verifier library.
  searchPathRef.set (builtin ++ [library])
  let (base, state) ← importData (baseModules external) default
  searchPathRef.set (builtin ++ [library, trusted])
  let (inputs, state) ← importData #[`SchemaInputs, `SqlInputs] state
  let inputEnv ← base.replay (← additions base inputs)
  let (approved, _) ← importData #[`Requirements, `Interpretation] state
  let trustedEnv ← inputEnv.replay (← additions inputEnv approved)
  let exported ← Export.parseStream stream
  let checked ← trustedEnv.replay (← exportedAdditions trustedEnv exported)
  checkTarget checked (exported.constMap.contains `Proofs.migrationCorrect)

/-- Exit 0 for a checked proof, 2 for a checked refutation, 1 for anything else. -/
def main (arguments : List String) : IO UInt32 := do
  try
    match arguments with
    | [library, trusted, bundle] => checkBundle library trusted bundle
    | _ => throw <| IO.userError "usage: migration-bundle-checker LIBRARY_DIR TRUSTED_DIR BUNDLE"
  catch error =>
    IO.eprintln s!"bundle checker rejected: {error}"
    return 1
