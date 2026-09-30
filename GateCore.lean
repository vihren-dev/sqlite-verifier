import Lean.Replay
import Lean.Util.FoldConsts

/-! Kernel-gate checks shared by the `.olean` gate and the exported-bundle checker.
They inspect declarations directly, never imported axiom caches, and never run
plugins, extensions or initializers. See `docs/kernel-gate.md` and ADR 0003. -/

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

/-- Reuse loaded module data only within one check, avoiding repeated trusted-library
reads and structural comparisons of separately loaded copies. Every stage still
compares and replays declarations; no plugins, extensions or initializers execute. -/
def importData (modules : Array Name) (state : ImportState) :
    IO (Environment × ImportState) := withImporting do
  let imports := modules.map fun name => { module := name : Import }
  let (_, state) ← (importModulesCore (globalLevel := .private) imports).run state
  let environment ← finalizeImport state imports {} 0
    (leakEnv := false) (loadExts := false) (level := .private)
  return (environment, state)

/-- Trusted-library modules imported by the user modules reachable from `roots`.

User modules are those whose `.olean` lies in one of `userDirs`; every other import
is a trusted module and must later resolve from the sysroot or verifier library.
Importing only these (plus `SqliteVerifier`) instead of all of `Lean` keeps the
gate's fixed cost low. A missing trusted module is not unsound: `additions` would
treat its declarations as fresh and replay them. -/
partial def trustedImports (userDirs : List System.FilePath) (roots : List Name)
    (seen : NameSet := {}) (found : NameSet := {}) : IO NameSet := do
  match roots with
  | [] => return found
  | name :: rest =>
    if seen.contains name then
      trustedImports userDirs rest seen found
    else
      let mut located := none
      for directory in userDirs do
        let path := modToFilePath directory name "olean"
        if located.isNone && (← path.pathExists) then
          located := some path
      match located with
      | none => trustedImports userDirs rest (seen.insert name) (found.insert name)
      | some path =>
        -- The import names live in the module's compacted region, so it is never freed;
        -- only a few small user modules are read per check.
        let (data, _) ← readModuleData path
        let imported := data.imports.toList.map (·.module)
        trustedImports userDirs (imported ++ rest) (seen.insert name) found

/-- Always include the protected library, which defines the verification target. -/
def baseModules (trusted : NameSet) : Array Name :=
  #[`SqliteVerifier] ++ (trusted.toList.filter (· != `SqliteVerifier)).toArray

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
    `NextInterpretation.next, `NextInterpretation.failures, `Generated.profile]
  let arguments ← names.mapM (closedConstant env)
  let target := mkAppN (mkConst `SqliteVerifier.VerificationConditions [logicalLevel])
    (#[logical] ++ arguments)
  unless (← kernelResult (Kernel.check env {} target)) == mkSort .zero do
    throw <| IO.userError "reconstructed verification target is not a proposition"
  return target

/-- Check the closed positive proof (exit 0) or refutation (exit 2) against the
independently reconstructed target, after auditing its transitive dependencies.
`positive` comes from the submitted declarations, before replay drops any unsafe or
partial ones, so such a proof is reported under its own name. -/
def checkTarget (checked : Environment) (positive : Bool) : IO UInt32 := do
  let expected ← expectedTarget checked
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

/-- Require the pinned sysroot and absolute existing directories for every trusted root. -/
def requireDirectories (directories : List System.FilePath) : IO System.FilePath := do
  let some sysroot ← IO.getEnv "LEAN_SYSROOT"
    | throw <| IO.userError "LEAN_SYSROOT must identify the pinned trusted Lean installation"
  for directory in System.FilePath.mk sysroot :: directories do
    unless directory.isAbsolute && (← directory.isDir) do
      throw <| IO.userError s!"expected absolute existing directory: {directory}"
  return sysroot

end ProofChecker
