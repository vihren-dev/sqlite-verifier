import Lean
import PublicDocSyntax

/-! Read direct compiler documentation and original source selections for the imported public API. -/

open Lean PublicDocInventory

/-- Locate the separately built model source beneath the repository root. -/
private def modelPackageDirectory : System.FilePath := "packages/belay-sqlite"

/-- Keep each kernel constant kind visible, including compiler-created recursors. -/
def constantKind : ConstantInfo → String
  | .axiomInfo _ => "axiom"
  | .defnInfo _ => "definition"
  | .thmInfo _ => "theorem"
  | .opaqueInfo _ => "opaque"
  | .quotInfo _ => "quotient"
  | .inductInfo _ => "inductive"
  | .ctorInfo _ => "constructor"
  | .recInfo _ => "recursor"

/-- Preserve compiler source locations without applying recursor-to-parent fallback. -/
def sourceSelection (range : DeclarationRange) : Json :=
  toJson #[range.pos.line - 1, range.charUtf16, range.endPos.line - 1, range.endCharUtf16]

/-- Read this declaration's own docstring; inherited or builtin documentation cannot fill a gap. -/
def constantMetadata (env : Environment) (info : ConstantInfo) : Json :=
  let name := info.name
  let verso := versoDocStringExt.find? (level := .server) env name |>.isSome
  let markdown := docStringExt.find? (level := .server) env name |>.isSome
  let ranges := declRangeExt.find? (level := .server) env name
  Json.mkObj [
    ("name", toJson name.toString), ("kind", toJson (constantKind info)),
    ("private", toJson (isPrivateName name)),
    ("instance", toJson (Meta.isInstanceCore env name)),
    ("documented", toJson (verso || markdown)), ("verso", toJson verso),
    ("selection", ranges.map (sourceSelection ·.selectionRange) |>.getD Json.null),
    ("range", ranges.map (sourceSelection ·.range) |>.getD Json.null),
    ("compiler_recursion_helper", toJson (isAuxRecursor env name || isNoConfusion env name))]

/-- Obtain module sources from the compiled import closure, rather than a fixed module-name list. -/
unsafe def readModules (root : System.FilePath) (entry : Name) : IO (Array Json) := do
  initSearchPath (← findSysroot)
  enableInitializersExecution
  let env ← importModules #[{ module := entry }] {} (loadExts := true)
  let mut modules := #[]
  for index in [:env.header.moduleNames.size] do
    let name := env.header.moduleNames[index]!
    let relative := System.FilePath.mk ("/".intercalate (name.components.map (·.toString))) |>.addExtension "lean"
    let localPath := root / relative
    let path ← if ← localPath.pathExists then pure localPath
      else pure (root / modelPackageDirectory / relative)
    if ← path.pathExists then
      let declarations ← readSourceDeclarators env path
      let ilean ← (← searchPathRef.get).findModuleWithExt "ilean" name
      let some ilean := ilean
        | throw <| IO.userError s!"Compiler references are missing for {name}; build the public library first"
      let constants := env.constants.toList.filterMap fun (constantName, info) => do
        let moduleIndex ← env.getModuleIdxFor? constantName
        if moduleIndex.toNat == index then some (constantMetadata env info) else none
      let checkedDocs := (getVersoModuleDoc? env name).getD #[] |>.map
        (sourceSelection ·.declarationRange)
      modules := modules.push <| Json.mkObj [
        ("module", toJson name.toString), ("source", toJson path.toString),
        ("references", toJson ilean.toString), ("declarators", toJson declarations),
        ("checked_module_documentation_ranges", toJson checkedDocs),
        ("constants", toJson constants)]
  if modules.isEmpty then
    throw <| IO.userError s!"Public module {entry} has no sources under {root}; supply its source directory"
  return modules

/-- Emit an inventory input from the exact compiled modules and their source files. -/
unsafe def main (arguments : List String) : IO UInt32 := do
  match arguments with
  | [root, entry, output] =>
    let modules ← readModules root entry.toName
    IO.FS.writeFile output <| (Json.mkObj [
      ("lean_version", toJson Lean.versionString), ("entry", toJson entry),
      ("modules", toJson modules)]).pretty
    return 0
  | _ =>
    IO.eprintln "Documentation inventory needs SOURCE_ROOT ENTRY_MODULE OUTPUT; build the library and supply these arguments"
    return 2
