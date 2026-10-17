import Belay.Sqlite.Json.Path

set_option doc.verso true

/-! The byte offsets of nodes in SQLite's JSONB encoding of a parsed JSON text, and a path
lookup that keeps them. {lit}`json_each` reports the offset of a node as its {lit}`id`
column ({lit}`jsonEachColumn` in 3.51.0), so the model must know where each node starts
in the JSONB that {lit}`jsonTranslateTextToBlob` builds. -/

namespace Belay.Sqlite.Json

/-- The size of a JSONB node header for a payload of {lit}`size` bytes: 1 byte up to 11,
2 bytes up to 255, 3 bytes up to 65535, else 5 bytes. {lit}`jsonBlobAppendNode` reserves a
header and {lit}`jsonBlobChangePayloadSize` resizes it to this size when the payload of a
container is known, so the final JSONB never has a 9-byte header. -/
def jsonbHeaderSize (size : Nat) : Nat :=
  if size ≤ 11 then 1 else if size ≤ 0xff then 2 else if size ≤ 0xffff then 3 else 5

mutual
/-- The payload size of a node in JSONB: 0 for the literals, the stored bytes of a number
or a string, and the encodings of the children of an array or an object. -/
def jsonbPayloadSize : JsonNode → Nat
  | .null | .true | .false => 0
  | .int payload | .int5 payload | .float payload | .float5 payload => payload.length
  | .text payload | .textj payload | .text5 payload | .textraw payload => payload.length
  | .array items => jsonbItemsSize items
  | .object members => jsonbMembersSize members

/-- The total JSONB size of the elements of an array. -/
def jsonbItemsSize : List JsonNode → Nat
  | [] => 0
  | item :: rest => jsonbHeaderSize (jsonbPayloadSize item) + jsonbPayloadSize item + jsonbItemsSize rest

/-- The total JSONB size of the members of an object: each label and each value. -/
def jsonbMembersSize : List (JsonNode × JsonNode) → Nat
  | [] => 0
  | (label, value) :: rest =>
    jsonbHeaderSize (jsonbPayloadSize label) + jsonbPayloadSize label +
      jsonbHeaderSize (jsonbPayloadSize value) + jsonbPayloadSize value + jsonbMembersSize rest
end

/-- The JSONB size of a node: its header and its payload. -/
def jsonbSize (node : JsonNode) : Nat := jsonbHeaderSize (jsonbPayloadSize node) + jsonbPayloadSize node

/-- The offset of the first child of a container that starts at {lit}`offset`: the
offset after its header. -/
def jsonbChildrenStart (node : JsonNode) (offset : Nat) : Nat :=
  offset + jsonbHeaderSize (jsonbPayloadSize node)

/-- A node found by a path lookup, with its JSONB offset, and the offset of its label
when the last path step selected an object member ({lit}`JsonParse.iLabel`). -/
structure LocatedNode where
  /-- The node that the path selects. -/
  node : JsonNode
  /-- The JSONB offset of the node. -/
  offset : Nat
  /-- The JSONB offset of the label before the node, when the node is a member value. -/
  labelOffset : Option Nat

/-- The offset of element {lit}`index` of an array whose children start at
{lit}`offset`. -/
def jsonbItemOffset (items : List JsonNode) (index : Nat) (offset : Nat) : Nat :=
  offset + jsonbItemsSize (items.take index)

/-- The first member whose label equals the key, as {name}`findMember` finds it, with the
offsets of its label and its value: {lit}`none` when no label matches, and
{lit}`some none` for a label that is not a string. -/
def findMemberAt (key : List UInt8) (rawKey : Bool) :
    List (JsonNode × JsonNode) → Nat → Option (Option (Nat × Nat × JsonNode))
  | [], _ => none
  | (label, value) :: rest, offset =>
    match label.labelText with
    | none => some none
    | some (text, rawLabel) =>
      if labelsMatch key rawKey text rawLabel then some (some (offset, offset + jsonbSize label, value))
      else findMemberAt key rawKey rest (offset + jsonbSize label + jsonbSize value)

/-- Follow the path from {lit}`position` as {name}`lookupStep` does ({lit}`jsonLookupStep`),
and keep the JSONB offsets. The outer {lit}`none` is a path error or malformed JSONB, which
{lit}`json_each` both reports as a bad path; {lit}`some none` is "not found". -/
def locateStep (path : Array UInt8) : Nat → Nat → LocatedNode → Option (Option LocatedNode)
  | 0, _, _ => none
  | fuel + 1, position, located =>
    let byte := byteAt path position
    if byte == 0 then some (some located)
    else if byte == 46 then
      match readPathLabel path (position + 1) with
      | none => none
      | some (key, rawKey, next) =>
        match located.node with
        | .object members =>
          match findMemberAt key rawKey members (jsonbChildrenStart located.node located.offset) with
          | none => some none
          | some none => none
          | some (some (labelOffset, valueOffset, value)) =>
            locateStep path fuel next ⟨value, valueOffset, some labelOffset⟩
        | .null | .true | .false | .int _ | .int5 _ | .float _ | .float5 _ | .text _ | .textj _ | .text5 _
        | .textraw _ | .array _ => some none
    else if byte == 91 then
      match located.node with
      | .array items =>
        match readPathIndex path position items.length with
        | none => none
        | some none => some none
        | some (some (index, close)) =>
          match items[index.toNat]? with
          | some item =>
            let offset := jsonbItemOffset items index.toNat (jsonbChildrenStart located.node located.offset)
            locateStep path fuel (close + 1) ⟨item, offset, none⟩
          | none => some none
      | .null | .true | .false | .int _ | .int5 _ | .float _ | .float5 _ | .text _ | .textj _ | .text5 _
      | .textraw _ | .object _ => some none
    else none

/-- Look up a path text after its {lit}`$` in a whole document, whose root is at JSONB
offset 0. -/
def locatePath (path : List UInt8) (root : JsonNode) : Option (Option LocatedNode) :=
  locateStep path.toArray (path.length + 2) 1 ⟨root, 0, none⟩

end Belay.Sqlite.Json
