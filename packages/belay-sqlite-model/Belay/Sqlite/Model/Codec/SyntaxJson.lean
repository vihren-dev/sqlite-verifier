import Belay.Sqlite.Model.Codec

set_option doc.verso true

/-! JSON transport of statement syntax: the derived instances of its types, the table options
with {lit}`strict` only for a {lit}`STRICT` table, and statements with each default field
({lit}`subqueries`, {lit}`having`, {lit}`distinct`, {lit}`compound`) only when it differs from its default, so that the records of earlier statements keep their form. -/

namespace Belay.Sqlite.Model

deriving instance Lean.FromJson, Lean.ToJson for Comparison, ArithmeticOperator
deriving instance Lean.FromJson, Lean.ToJson for ConflictAlgorithm
deriving instance Lean.FromJson, Lean.ToJson for Syntax.QuoteKind
deriving instance Lean.FromJson, Lean.ToJson for Syntax.ForeignKeyAction
deriving instance Lean.FromJson, Lean.ToJson for Syntax.RaiseKind
deriving instance Lean.FromJson, Lean.ToJson for Syntax.Expr, Syntax.DefaultExpression, Syntax.ColumnConstraint
deriving instance Lean.FromJson, Lean.ToJson for Syntax.ResultColumn, Syntax.OrderTerm
deriving instance Lean.FromJson, Lean.ToJson for Syntax.ColumnDefinition, Syntax.TableConstraint
deriving instance Lean.FromJson, Lean.ToJson for Syntax.TableReference, Syntax.Join
deriving instance Lean.FromJson, Lean.ToJson for CompoundOperator, Syntax.Compound, Syntax.Subquery
deriving instance Lean.FromJson, Lean.ToJson for Syntax.ConflictAction, Syntax.ConflictClause
deriving instance Lean.FromJson, Lean.ToJson for Syntax.TriggerTime, Syntax.TriggerEvent, Syntax.BodyStatement
deriving instance Lean.FromJson, Lean.ToJson for Syntax.PragmaSetting, Syntax.Pragma
/-- The table options as JSON, with {lit}`strict` only for a {lit}`STRICT` table, so the
records of other tables keep their form. -/
instance : Lean.ToJson Syntax.TableOptions where
  toJson options := Lean.Json.mkObj ([("withoutRowid", Lean.toJson options.withoutRowid)] ++
    (if options.strict then [("strict", Lean.toJson true)] else []))

/-- Read the table options ({name}`Syntax.TableOptions`); a missing {lit}`strict` is a table
that is not {lit}`STRICT`. -/
instance : Lean.FromJson Syntax.TableOptions where
  fromJson? json := do
    let strict : Bool := (json.getObjValAs? Bool "strict").toOption.getD false
    return { withoutRowid := ← json.getObjValAs? Bool "withoutRowid", strict }
deriving instance Lean.FromJson, Lean.ToJson for Syntax.Statement

/-- The derived reader of a statement, which needs every field. -/
def Syntax.Statement.derivedFromJson : Lean.FromJson Syntax.Statement := inferInstance

/-- The fields of statement constructors that the frontend writes only when they differ from
their default, so the records of statements without them keep the form that they had before
the field existed: each constructor's JSON name, the field, and its default. -/
def Syntax.Statement.defaultFields : List (String × String × Lean.Json) :=
  [("select", "subqueries", .arr #[]), ("insert", "subqueries", .arr #[]), ("update", "subqueries", .arr #[]),
   ("delete", "subqueries", .arr #[]), ("select", "having", .null), ("select", "distinct", .bool false),
   ("select", "compound", .null)]

/-- The JSON of a statement with each missing field of {name}`Syntax.Statement.defaultFields`
added with its default to the object of its constructor. Any other JSON stays as it is, so the
derived reader reports its own error for it. -/
def Syntax.Statement.withDefaultFields (json : Lean.Json) : Lean.Json :=
  Syntax.Statement.defaultFields.foldl (fun json (key, field, default) => match json, json.getObjVal? key with
    | .obj outer, .ok (.obj fields) => match fields.get? field with
      | some _ => json
      | none => .obj (outer.insert key (.obj (fields.insert field default)))
    | _, _ => json) json

/-- The derived writer of a statement, which writes every field. -/
def Syntax.Statement.derivedToJson : Lean.ToJson Syntax.Statement := inferInstance

/-- The JSON of a statement without each field of {name}`Syntax.Statement.defaultFields` that
has its default, the form that the frontend writes ({name}`Syntax.Statement.withDefaultFields`
reads it back). -/
def Syntax.Statement.withoutDefaultFields (json : Lean.Json) : Lean.Json :=
  Syntax.Statement.defaultFields.foldl (fun json (key, field, default) => match json, json.getObjVal? key with
    | .obj outer, .ok (.obj fields) =>
      if fields.get? field == some default then .obj (outer.insert key (.obj (fields.erase field))) else json
    | _, _ => json) json

/-- Write a statement ({name}`Syntax.Statement.derivedToJson`) without its default fields
({name}`Syntax.Statement.withoutDefaultFields`). -/
instance (priority := high) : Lean.ToJson Syntax.Statement where
  toJson statement := Syntax.Statement.withoutDefaultFields (Syntax.Statement.derivedToJson.toJson statement)

/-- Read a statement ({name}`Syntax.Statement.derivedFromJson`), with each missing default field
read as its default ({name}`Syntax.Statement.withDefaultFields`). -/
instance (priority := high) : Lean.FromJson Syntax.Statement where
  fromJson? json := Syntax.Statement.derivedFromJson.fromJson? (Syntax.Statement.withDefaultFields json)

end Belay.Sqlite.Model
