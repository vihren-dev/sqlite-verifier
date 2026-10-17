set_option doc.verso true

/-! The parse tree of a JSON text and the errors of the JSON functions. The tree has the
node types of SQLite's binary JSON format (JSONB, SQLite 3.51.0 {lit}`JSONB_NULL` to
{lit}`JSONB_OBJECT`) with their payload bytes, because SQLite renders a node and converts
it to an SQL value from its type and its payload. -/

namespace Belay.Sqlite.Json

/-- A node of a parsed JSON text, as SQLite stores it in JSONB. A scalar node keeps
its payload: the bytes of the source text that SQLite copies into the node. -/
inductive JsonNode where
  /-- The literal {lit}`null` ({lit}`JSONB_NULL`); also the JSON5 {lit}`NaN`. -/
  | null
  /-- The literal {lit}`true` ({lit}`JSONB_TRUE`). -/
  | true
  /-- The literal {lit}`false` ({lit}`JSONB_FALSE`). -/
  | false
  /-- A decimal integer in canonical JSON form ({lit}`JSONB_INT`), for example
  {lit}`-12`. A JSON5 leading plus sign is not part of the payload. -/
  | int (payload : List UInt8)
  /-- A hexadecimal JSON5 integer ({lit}`JSONB_INT5`), for example {lit}`0x1F`. -/
  | int5 (payload : List UInt8)
  /-- A number with a fraction or an exponent in canonical JSON form
  ({lit}`JSONB_FLOAT`), for example {lit}`1.50`. JSON5 infinities are {lit}`9e999`. -/
  | float (payload : List UInt8)
  /-- A JSON5 number with no digit on one side of the point ({lit}`JSONB_FLOAT5`),
  for example {lit}`.5` or {lit}`5.`. -/
  | float5 (payload : List UInt8)
  /-- A string with no escapes ({lit}`JSONB_TEXT`); the payload is the bytes between
  the quotes. -/
  | text (payload : List UInt8)
  /-- A string with canonical JSON escapes only ({lit}`JSONB_TEXTJ`). -/
  | textj (payload : List UInt8)
  /-- A string with JSON5 escapes, raw control bytes or a raw double quote
  ({lit}`JSONB_TEXT5`). -/
  | text5 (payload : List UInt8)
  /-- SQL text that needs escapes in JSON ({lit}`JSONB_TEXTRAW`). The reader never
  makes it; the JSON functions that store SQL text in JSON do. -/
  | textraw (payload : List UInt8)
  /-- An array with its elements in order ({lit}`JSONB_ARRAY`). -/
  | array (items : List JsonNode)
  /-- An object with its members in order ({lit}`JSONB_OBJECT`): pairs of a label node
  and a value node. Duplicate labels stay. -/
  | object (members : List (JsonNode × JsonNode))
  deriving Repr, Inhabited

/-- A run-time error of a JSON function. -/
inductive JsonError where
  /-- The error {lit}`malformed JSON`. -/
  | malformed
  /-- The error {lit}`bad JSON path: '%s'`, with the path text that SQLite reports. -/
  | badPath (path : List UInt8)
  /-- A BLOB argument (JSONB): the model does not describe it. -/
  | blobArgument
  /-- The error {lit}`FLAGS parameter to json_valid() must be between 1 and 15`. -/
  | badFlags
  deriving Repr, DecidableEq

/-- The label text of an object member and whether it has no escapes, as
{lit}`jsonLookupStep` reads it: {lit}`none` for a node that is not a string, which
SQLite reports as malformed JSONB. -/
def JsonNode.labelText : JsonNode → Option (List UInt8 × Bool)
  | .text payload | .textraw payload => some (payload, Bool.true)
  | .textj payload | .text5 payload => some (payload, Bool.false)
  | .null | .true | .false | .int _ | .int5 _ | .float _ | .float5 _ | .array _ | .object _ => none

end Belay.Sqlite.Json
