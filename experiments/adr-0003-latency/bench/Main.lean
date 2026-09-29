import Lean
import Export.Parse

/-! ADR 0003 latency experiment: time checking of a lean4export NDJSON proof closure.

`full` replays every exported declaration into an empty environment, as comparator's
kernel step does. `trusted` imports the pinned `SqliteVerifier` library from its
`.olean` files, requires every exported declaration it already contains to match
after the exporter's normalization, and replays only the remaining declarations.
This measures cost only; it omits target reconstruction and the axiom audit. -/

open Lean

deriving instance BEq for QuotKind, QuotVal, InductiveVal, ConstantInfo

/-- Print the milliseconds spent in an action under a stable label. -/
def timed (label : String) (action : IO α) : IO α := do
  let start ← IO.monoMsNow
  let value ← action
  IO.println s!"{label}_ms={(← IO.monoMsNow) - start}"
  return value

/-- lean4export drops metadata and sets `let` nondep flags to false; apply the same here. -/
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

/-- Comparator-style replay of the whole exported closure into an empty environment. -/
def fullReplay (exported : Export.ExportedEnv) : IO Unit := do
  let env ← mkEmptyEnvironment
  let constMap := exported.constMap.erase `Quot.mk |>.erase `Quot.lift |>.erase `Quot.ind
  discard <| timed "full_replay" (env.replay constMap)

/-- Replay declarations absent from the trusted library; optionally split contract from candidate. -/
def trustedReplay (exported : Export.ExportedEnv) : IO Unit := do
  let env ← timed "library_import" (importModules #[{ module := `SqliteVerifier }] {} (loadExts := false))
  let mut fresh : Std.HashMap Name ConstantInfo := {}
  let start ← IO.monoMsNow
  for (name, info) in exported.constMap.toList do
    if let some trusted := env.toKernelEnv.find? name then
      unless info == trusted || normalizeInfo info == normalizeInfo trusted do
        throw <| IO.userError s!"exported declaration differs from the trusted library: {name}"
    else
      fresh := fresh.insert name info
  IO.println s!"compare_ms={(← IO.monoMsNow) - start} fresh={fresh.size}"
  let contractModules := ((← IO.getEnv "CONTRACT_MODULES").getD "").splitOn "," |>.filter (· ≠ "")
  if contractModules.isEmpty then
    discard <| timed "fresh_replay" (env.replay fresh)
  else
    -- Names defined by the approved contract and verifier-generated inputs.
    let contractEnv ← importModules (contractModules.toArray.map ({ module := ·.toName })) {} (loadExts := false)
    let (contract, candidate) := fresh.toList.partition fun (name, _) => (contractEnv.toKernelEnv.find? name).isSome
    IO.println s!"contract_fresh={contract.length} candidate_fresh={candidate.length}"
    let checked ← timed "contract_replay" (env.replay (Std.HashMap.ofList contract))
    discard <| timed "candidate_replay" (checked.replay (Std.HashMap.ofList candidate))

/-- Parse one export, report its size, then run the selected replay strategy. -/
def main (arguments : List String) : IO UInt32 := do
  let [mode, file] := arguments | throw <| IO.userError "usage: bench full|trusted EXPORT.ndjson"
  initSearchPath (← findSysroot)
  let exported ← timed "parse" do
    Export.parseStream (IO.FS.Stream.ofHandle (← IO.FS.Handle.mk file .read))
  IO.println s!"declarations={exported.constMap.size}"
  match mode with
  | "full" => fullReplay exported
  | "trusted" => trustedReplay exported
  | _ => throw <| IO.userError s!"unknown mode: {mode}"
  return 0
