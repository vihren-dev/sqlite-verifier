import VerifierConformance.Json

/-! Bounded-by-caller JSON-lines transport for the ADR 0004 compiled model.
--emit-lean serializes the decoded case as a closed term for kernel regression checks. -/

open Lean SqliteVerifier.Conformance

/-- Report transport problems independently of semantic agreement. -/
def harnessError (message : String) : Json :=
  Json.mkObj [("verdict", toJson "HARNESS_ERROR"), ("error", toJson message)]

/-- Both verdict and optional proof input originate in one decoded structural case. -/
def evaluateLine (line : String) (emitLean : Bool) : Json :=
  match Json.parse line >>= decodeCase with
  | .error message => harnessError message
  | .ok c =>
    let verdict := classifyCase c
    let (name, position) := match verdict with
      | .agree => ("AGREE", none)
      | .disagree position => ("DISAGREE", position)
      | .modelUnsupported => ("MODEL_UNSUPPORTED", none)
    Json.mkObj ([("verdict", toJson name), ("position", toJson position)] ++
      if emitLean then [("caseLean", toJson (reprStr c)), ("decoded", toJson c)] else [])

/-- Each input line produces exactly one result; malformed lines do not poison the stream. -/
def main (args : List String) : IO UInt32 := do
  let input ← IO.getStdin
  let output ← IO.getStdout
  unless args == [] || args == ["--emit-lean"] do
    (← IO.getStderr).putStrLn "usage: conformance-runner [--emit-lean]"
    return 2
  repeat
    let line ← input.getLine
    if line.isEmpty then break
    output.putStrLn ((evaluateLine line (args == ["--emit-lean"])).compress)
  return 0
