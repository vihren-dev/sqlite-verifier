import Lean

/-! Source declarators give the inventory an independent check on compiler references. -/

namespace PublicDocInventory
open Lean

/-- A source identifier's exact parser role and UTF-16 selection range. -/
structure SourceDeclarator where
  /-- Parser node that authored this identifier. -/
  parserKind : String
  /-- Declaration, constructor, field or example; coverage excludes anonymous examples. -/
  role : String
  /-- Original-source position in the compiler's LSP coordinate system. -/
  selection : Array Nat
  /-- An explicit anonymous instance has a keyword selection rather than a named binder. -/
  anonymousInstance : Bool := false
  /-- Exact source comment ranges; compiled Verso metadata must confirm they were checked. -/
  documentation : Array (Array Nat) := #[]
  deriving ToJson

/-- Locate documentation comments only inside the declaration's own modifiers. -/
partial def documentationRanges (text : FileMap) (node : Syntax) : Array (Array Nat) :=
  if node.isOfKind ``Parser.Command.docComment then
    match node.getRange? with
    | some range =>
      let lsp := range.toLspRange text
      #[#[lsp.start.line, lsp.start.character, lsp.end.line, lsp.end.character]]
    | none => #[]
  else node.getArgs.foldl (init := #[]) fun result child => result ++ documentationRanges text child

/-- Convert an original syntax token to the coordinates used in compiler reference files. -/
def sourceDeclarator (text : FileMap) (owner identifier : Syntax) (role : String)
    (documentation : Syntax := .missing) :
    Option SourceDeclarator := do
  let .original .. := identifier.getHeadInfo | none
  let range ← identifier.getRange?
  let lsp := range.toLspRange text
  return {
    parserKind := owner.getKind.toString
    role := role
    selection := #[lsp.start.line, lsp.start.character, lsp.end.line, lsp.end.character]
    anonymousInstance := owner.isOfKind ``Parser.Command.instance && identifier.isToken "instance"
    documentation := documentationRanges text documentation
  }

/-- Capture every identifier in a grouped field binder, using its original parser token. -/
def fieldDeclarators (text : FileMap) (node : Syntax) : Array SourceDeclarator :=
  let identifiers := if node.isOfKind ``Parser.Command.structSimpleBinder then #[node[1]]
    else node[2].getArgs
  identifiers.filterMap (fun identifier => sourceDeclarator text node identifier "field" node[0])

/-- Inspect declaration interiors for explicit constructors and all structure field forms. -/
partial def nestedDeclarators (text : FileMap) (node : Syntax) : Array SourceDeclarator := Id.run do
  let mut result := #[]
  if node.isOfKind ``Parser.Command.ctor then
    result := (sourceDeclarator text node node[3] "constructor" (mkNullNode #[node[0], node[2]])).toArray
  else if node.isOfKind ``Parser.Command.structCtor then
    result := (sourceDeclarator text node node[1] "constructor" node[0]).toArray
  else if node.isOfKind ``Parser.Command.structSimpleBinder ||
      node.isOfKind ``Parser.Command.structExplicitBinder ||
      node.isOfKind ``Parser.Command.structImplicitBinder ||
      node.isOfKind ``Parser.Command.structInstBinder then
    result := fieldDeclarators text node
  else if node.isOfKind ``Parser.Command.computedField then
    result := (sourceDeclarator text node node[1] "field" node[0]).toArray
  for child in node.getArgs do
    result := result ++ nestedDeclarators text child
  return result

/-- Inspect commands without mistaking quoted declarations inside proof terms for API declarations. -/
partial def commandDeclarators (text : FileMap) (node : Syntax) : Array SourceDeclarator :=
  if node.isOfKind ``Parser.Command.declaration then
    let body := node[1]
    let role := if body.isOfKind ``Parser.Command.example then "example" else "declaration"
    let selected := (sourceDeclarator text body (Elab.getDeclarationSelectionRef body) role node[0]).toArray
    selected ++ nestedDeclarators text body
  else node.getArgs.foldl (init := #[]) fun result child =>
    result ++ commandDeclarators text child

/-- Parse the real source with the compiled environment's syntax extensions. -/
def readSourceDeclarators (env : Environment) (path : System.FilePath) : IO (Array SourceDeclarator) := do
  let contents ← IO.FS.readFile path
  let tree ← Parser.testParseModule env path.toString contents
  return commandDeclarators (FileMap.ofString contents) tree

end PublicDocInventory
