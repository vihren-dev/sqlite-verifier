import Lean.Replay
import Lean.Util.FoldConsts

/-! Kernel-gate checks inspect declarations directly, never imported axiom caches. -/

open Lean

namespace ProofChecker

deriving instance BEq for InductiveVal, QuotKind, QuotVal, ConstantInfo

/-- Reject substitutions of any declaration already fixed by a sealed environment. -/
def additions (base imported : Environment) : IO (Std.HashMap Name ConstantInfo) := do
  let mut fresh := {}
  for (name, info) in imported.constants.toList do
    if let some trusted := base.toKernelEnv.find? name then
      unless info == trusted do
        throw <| IO.userError s!"modified protected declaration: {name}"
    else
      fresh := fresh.insert name info
  return fresh

/-- Audit the actual transitive types and bodies, including opaque values. -/
partial def audit (env : Environment) (pending : List Name)
    (seen : NameSet := {}) : IO Unit := do
  match pending with
  | [] => pure ()
  | name :: rest =>
    if seen.contains name then
      audit env rest seen
    else
      let some info := env.toKernelEnv.find? name
        | throw <| IO.userError s!"missing proof dependency: {name}"
      if info.isUnsafe || info.isPartial then
        throw <| IO.userError s!"unsafe or partial dependency: {name}"
      if info.isAxiom && !([`propext, `Classical.choice, `Quot.sound].contains name) then
        throw <| IO.userError s!"unapproved axiom: {name}"
      audit env (info.getUsedConstantsAsSet.toList ++ rest) (seen.insert name)

/-- Convert kernel errors to failing process diagnostics without using elaborator state. -/
def kernelResult {α : Type} (result : Except Kernel.Exception α) : IO α := do
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError (← error.toMessageData {} |>.toString)

end ProofChecker

open ProofChecker

/-- Import only kernel data: candidate extension caches and initializers never execute. -/
def importData (modules : Array Name) : IO Environment :=
  importModules (modules.map fun name => { module := name }) {}
    (trustLevel := 0) (plugins := #[]) (loadExts := false) (level := .private)

/-- Require closed input constants; no implicit extra universe or value assumptions. -/
def closedConstant (env : Environment) (name : Name) : IO Expr := do
  let some info := env.toKernelEnv.find? name
    | throw <| IO.userError s!"missing required declaration: {name}"
  unless info.levelParams.isEmpty do
    throw <| IO.userError s!"required declaration has uninstantiated universes: {name}"
  return mkConst name

/-- Build the exact target without using the candidate's Generated.expected declaration. -/
def expectedTarget (env : Environment) : IO Expr := do
  let logical ← closedConstant env `Requirements.LogicalState
  let logicalType ← kernelResult (Kernel.check env {} logical)
  let .sort level ← kernelResult (Kernel.whnf env {} logicalType)
    | throw <| IO.userError "Requirements.LogicalState must be a type"
  let some logicalLevel := level.normalize.dec
    | throw <| IO.userError "Requirements.LogicalState must inhabit Type"
  let names := #[`Generated.startSchema, `Generated.nextSchema, `Generated.script,
    `Interpretation.admitted, `Requirements.contract, `Interpretation.current,
    `NextInterpretation.next, `NextInterpretation.failures]
  let arguments ← names.mapM (closedConstant env)
  let target := mkAppN (mkConst `SqliteVerifier.VerificationConditions [logicalLevel])
    (#[logical] ++ arguments)
  unless (← kernelResult (Kernel.check env {} target)) == mkSort .zero do
    throw <| IO.userError "reconstructed verification target is not a proposition"
  return target

/-- Replay user-stage declarations against the pinned library, then check the actual proof. -/
def checkProof (library trusted candidate : System.FilePath) : IO UInt32 := do
  let some sysroot ← IO.getEnv "LEAN_SYSROOT"
    | throw <| IO.userError "LEAN_SYSROOT must identify the pinned trusted Lean installation"
  for directory in [System.FilePath.mk sysroot, library, trusted, candidate] do
    unless directory.isAbsolute && (← directory.isDir) do
      throw <| IO.userError s!"expected absolute existing directory: {directory}"
  let builtin ← getBuiltinSearchPath sysroot
  -- Deliberately ignore LEAN_PATH and never search a candidate directory before trusted roots.
  searchPathRef.set (builtin ++ [library])
  let base ← importData #[`Lean, `SqliteVerifier]
  searchPathRef.set (builtin ++ [library, trusted])
  let sealed ← importData #[`Requirements, `Interpretation, `SqlInputs]
  let trustedEnv ← base.replay (← additions base sealed)
  searchPathRef.set (builtin ++ [library, trusted, candidate])
  let imported ← importData #[`Proofs]
  let checked ← trustedEnv.replay (← additions trustedEnv imported)
  let expected ← expectedTarget checked
  let positive := (imported.toKernelEnv.find? `Proofs.migrationCorrect).isSome
  let name := if positive then `Proofs.migrationCorrect else `Proofs.migrationViolated
  let target := if positive then expected else mkApp (mkConst ``Not) expected
  let proof ← closedConstant checked name
  audit checked (name :: target.getUsedConstants.toList)
  let some info := checked.toKernelEnv.find? name
    | throw <| IO.userError "proof declaration disappeared"
  let some body := info.value? (allowOpaque := true)
    | throw <| IO.userError "proof must have a checked body"
  let actualType ← kernelResult (Kernel.check checked {} body)
  discard <| kernelResult (Kernel.check checked {} proof)
  unless ← kernelResult (Kernel.isDefEq checked {} actualType target) do
    throw <| IO.userError "proof does not establish the reconstructed verification target"
  return if positive then 0 else 2

/-- Exit zero only after replay, axiom audit, and the fixed target comparison all succeed. -/
def main (arguments : List String) : IO UInt32 := do
  try
    match arguments with
    | [library, trusted, candidate] =>
      checkProof library trusted candidate
    | _ =>
      throw <| IO.userError
        "usage: migration-proof-checker LIBRARY_DIR TRUSTED_DIR CANDIDATE_DIR"
  catch error =>
    IO.eprintln s!"kernel gate rejected: {error}"
    return 1
