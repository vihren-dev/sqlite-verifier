import Lean

/-! Ordered installed roots and exact module files for the kernel gates. -/

open Lean

namespace ProofChecker

/-- Require the pinned sysroot and absolute existing directories for every trusted root. -/
def requireDirectories (directories : List System.FilePath) : IO System.FilePath := do
  let some sysroot ← IO.getEnv "LEAN_SYSROOT"
    | throw <| IO.userError "LEAN_SYSROOT must identify the pinned trusted Lean installation"
  for directory in System.FilePath.mk sysroot :: directories do
    unless directory.isAbsolute && (← directory.isDir) do
      throw <| IO.userError s!"expected absolute existing directory: {directory}"
  return sysroot


/-- Resolve the pinned sysroot, application and model roots, refusing duplicate
installed modules before any caller stage is exposed. -/
def requireLibraryRoots (application model : System.FilePath) : IO SearchPath := do
  let sysroot ← requireDirectories [application, model]
  let roots := (← getBuiltinSearchPath sysroot) ++ [application, model]
  let mut modules : Std.HashMap String System.FilePath := {}
  for root in roots do
    for path in (← root.walkDir) do
      if path.extension == some "olean" then
        let name := (String.intercalate "/" (path.components.drop root.components.length)).toLower
        if let some previous := modules[name]? then
          throw <| IO.userError
            s!"installed module {path} conflicts with {previous}; rebuild or reinstall"
        modules := modules.insert name path
  return roots


/-- Supply exact files for project and caller modules. The first existing module
in the ordered roots wins, including when a caller adds a sibling below an
installed namespace. Builtin modules retain Lean's standard resolution. -/
def explicitArtifacts (roots : SearchPath) : IO (NameMap ImportArtifacts) := do
  let builtin ← getBuiltinSearchPath (← requireDirectories [])
  let mut artifacts : NameMap ImportArtifacts := {}
  for directory in roots do
    if builtin.contains directory then continue
    for path in (← directory.walkDir) do
      if path.extension != some "olean" then continue
      let parts := (path.withExtension "").components.drop directory.components.length
      let name := parts.foldl Name.str .anonymous
      if artifacts.contains name then continue
      let mut chosen := path
      for root in roots do
        let candidate := modToFilePath root name "olean"
        if ← candidate.pathExists then
          chosen := candidate
          break
      let mut data := #[chosen]
      for level in [OLeanLevel.server, OLeanLevel.private] do
        let part := level.adjustFileName chosen
        if ← part.pathExists then data := data.push part else break
      let mut ir := #[]
      if ← (chosen.withExtension "ir.sig").pathExists then
        ir := #[chosen.withExtension "ir.sig"]
        if ← (chosen.withExtension "ir").pathExists then
          ir := ir.push (chosen.withExtension "ir")
      artifacts := artifacts.insert name (.ofArrays #[data, ir])
  return artifacts

end ProofChecker
