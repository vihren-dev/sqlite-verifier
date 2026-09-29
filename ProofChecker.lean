import GateCore

/-! The `.olean` kernel gate used by `migration-check verify`. -/

open Lean ProofChecker

/-- Replay user-stage declarations against the pinned library, then check the actual proof. -/
def checkProof (library trusted candidate : System.FilePath) : IO UInt32 := do
  let sysroot ← requireDirectories [library, trusted, candidate]
  let builtin ← getBuiltinSearchPath sysroot
  -- Only the user modules' trusted imports form the base; they resolve without user directories.
  let external ← trustedImports [trusted, candidate]
    [`SchemaInputs, `SqlInputs, `Requirements, `Interpretation, `Proofs]
  -- Deliberately ignore LEAN_PATH and never search a candidate directory before trusted roots.
  searchPathRef.set (builtin ++ [library])
  let (base, state) ← importData (baseModules external) default
  searchPathRef.set (builtin ++ [library, trusted])
  -- Fix generated inputs first: even approved definitions cannot replace the supplied schema.
  let (inputs, state) ← importData #[`SchemaInputs, `SqlInputs] state
  let inputEnv ← base.replay (← additions base inputs)
  let (approved, state) ← importData #[`Requirements, `Interpretation] state
  let trustedEnv ← inputEnv.replay (← additions inputEnv approved)
  searchPathRef.set (builtin ++ [library, trusted, candidate])
  let (imported, _) ← importData #[`Proofs] state
  let checked ← trustedEnv.replay (← additions trustedEnv imported)
  checkTarget checked (imported.toKernelEnv.find? `Proofs.migrationCorrect).isSome

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
