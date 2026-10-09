import GateCore

/-! The `.olean` kernel gate used by `migration-check verify`. -/

open Lean ProofChecker

/-- Replay user-stage declarations against the pinned library, then check the actual proof. -/
def checkProof (library model trusted candidate : System.FilePath) : IO UInt32 := do
  discard <| requireDirectories [trusted, candidate]
  let libraries ← requireLibraryRoots library model
  -- Only the user modules' trusted imports form the base; they resolve without user directories.
  let external ← trustedImports [trusted, candidate]
    [`SchemaInputs, `SqlInputs, `Requirements, `Interpretation, `Proofs]
  -- Deliberately ignore LEAN_PATH and never search a candidate directory before trusted roots.
  searchPathRef.set (libraries)
  let (base, state) ← importData (baseModules external) default
  searchPathRef.set (libraries ++ [trusted])
  -- Fix generated inputs first: even approved definitions cannot replace the supplied schema.
  let (inputs, state) ← importData #[`SchemaInputs, `SqlInputs] state
  let inputEnv := Environment.ofKernelEnv (← base.toKernelEnv.replay (← additions base inputs))
  let (approved, state) ← importData #[`Requirements, `Interpretation] state
  let trustedEnv := Environment.ofKernelEnv (← inputEnv.toKernelEnv.replay (← additions inputEnv approved))
  searchPathRef.set (libraries ++ [trusted, candidate])
  let (imported, _) ← importData #[`Proofs] state
  let checked := Environment.ofKernelEnv (← trustedEnv.toKernelEnv.replay (← additions trustedEnv imported))
  checkTarget checked (imported.toKernelEnv.find? `Proofs.migrationCorrect).isSome

/-- Exit zero only after replay, axiom audit, and the fixed target comparison all succeed. -/
def main (arguments : List String) : IO UInt32 := do
  try
    match arguments with
    | [library, model, trusted, candidate] =>
      checkProof library model trusted candidate
    | _ =>
      throw <| IO.userError
        "usage: migration-proof-checker APPLICATION_LIBRARY_DIR MODEL_LIBRARY_DIR TRUSTED_DIR CANDIDATE_DIR"
  catch error =>
    IO.eprintln s!"kernel gate rejected: {error}"
    return 1
