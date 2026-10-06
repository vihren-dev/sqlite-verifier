import Export

/-! Export proof dependencies while omitting declarations supplied by explicit trusted imports.

This producer uses unpatched lean4export. The checker still imports and checks its
own trusted base. Module origins select omissions, so a candidate can use any namespace.
-/

open Lean

namespace ProofExporter

/-- Export options supplied unchanged to lean4export's state initializer. -/
def exportOptions : List String := ["--export-mdata", "--export-unsafe", "--ignore-missing"]

/-- Decode one Lean name and identify malformed input before importing or exporting modules. -/
def decodeName (value : String) : IO Name := do
  let some name := Syntax.decodeNameLit ("`" ++ value)
    | throw <| IO.userError s!"invalid Lean name: {value}; supply a module or declaration name"
  if name == .anonymous then
    throw <| IO.userError "empty Lean name; supply a module or declaration name"
  return name

/-- Direct and transitive imports of the selected roots in the loaded environment. -/
partial def importClosure (env : Environment) (pending : List Name)
    (seen : NameSet := {}) : NameSet :=
  match pending with
  | [] => seen
  | name :: rest =>
    if seen.contains name then importClosure env rest seen
    else
      let direct := match env.getModuleIdx? name with
        | some idx => env.header.moduleData[idx.toNat]!.imports.toList.map (·.module)
        | none => []
      importClosure env (direct ++ rest) (seen.insert name)

/-- Declarations provided by the closure, using their source modules rather than namespaces. -/
def baseConstants (env : Environment) (closure : NameSet) : NameHashSet := Id.run do
  let modules := env.header.moduleNames
  let mut result : NameHashSet := {}
  for (name, _) in env.constants.toList do
    if let some idx := env.getModuleIdxFor? name then
      if closure.contains modules[idx.toNat]! then
        result := result.insert name
  return result

/-- Produce upstream NDJSON for selected roots with an explicitly omitted import closure. -/
def exportProof (arguments : List String) : IO Unit := do
  let (flags, arguments) := arguments.partition (fun value => value.startsWith "--" && value.length ≥ 3)
  let omissionFlags := flags.filter (·.startsWith "--omit=")
  let options := flags.filter (!·.startsWith "--omit=")
  for option in options do
    unless exportOptions.contains option do
      throw <| IO.userError s!"unknown exporter option: {option}; use --omit=MODULE or a lean4export option"
  let omitted ← omissionFlags.mapM (fun value => decodeName (value.drop 7).toString)
  let (modules, roots) := arguments.span (· != "--")
  if modules.isEmpty then
    throw <| IO.userError "no export module supplied; use migration-proof-exporter MODULE -- DECLARATION"
  let imports ← modules.toArray.mapM fun value => do
    return { module := ← decodeName value : Import }
  initSearchPath (← findSysroot)
  let env ← importModules imports {}
  for name in omitted do
    unless (env.getModuleIdx? name).isSome do
      throw <| IO.userError s!"omitted module is not imported: {name}; choose a module in the export import closure"
  let constants ← match roots.tail? with
    | some names => names.mapM decodeName
    | none => pure <| env.constants.toList.map Prod.fst |>.filter (!·.isInternal)
  M.run env do
    initState env options
    modify fun state => { state with visitedConstants := baseConstants env (importClosure env omitted) }
    dumpMetadata
    for name in constants do
      modify fun state => { state with noMDataExprs := {} }
      dumpConstant name

end ProofExporter

/-- Exit successfully only when the requested export completes; preserve a useful failure diagnostic. -/
def main (arguments : List String) : IO UInt32 := do
  try
    ProofExporter.exportProof arguments
    return 0
  catch error =>
    IO.eprintln s!"proof export failed: {error}"
    return 1
