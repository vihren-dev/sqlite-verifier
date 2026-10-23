import Belay.Sqlite.Model.Resolution.TriggerBodies
import Belay.Sqlite.Model.Resolution.ForeignKeyPlan
import Belay.Sqlite.Model.Resolution.ConflictPolicy

set_option doc.verso true

/-! The trigger programs of a write (ADR 0018, D5). SQLite prepares, with a write, the program
of every trigger that the write fires, and of every trigger that the writes of those programs
and of the foreign-key actions fire in turn, each trigger once; an error in any of them is a
prepare error of the write. Resolution follows the same closure over {lit}`FireRequest`:
the writes that may fire triggers, with the conflict algorithm that their programs inherit. -/

namespace Belay.Sqlite.Model

/-- A write that may fire triggers: its table, its event (an UPDATE with its {lit}`SET`
columns), whether its own triggers fire (not for the DELETE of DROP TABLE, and for the rows that
REPLACE deletes only with recursive triggers on), the conflict algorithm of the write, which the programs that it fires
inherit, and whether it is a statement of a trigger's body, whose foreign keys resolution checks
here. -/
structure FireRequest where
  /-- The catalog position of the written table. -/
  table : Nat
  /-- The event of the write. -/
  event : Resolved.TriggerEvent
  /-- Whether the triggers of the table fire. -/
  fire : Bool := true
  /-- The conflict algorithm of the write, none for its default. -/
  algorithm : Option ConflictAlgorithm := none
  /-- Whether the write is a statement of a trigger's body. -/
  body : Bool := false
  deriving Repr, DecidableEq

/-- The resolved event of a trigger of a table with the columns ({name}`Resolved.TriggerEvent`). -/
def triggerEvent (columns : List CatalogColumn) : Syntax.TriggerEvent → Resolved.TriggerEvent
  | .insert => .insert
  | .delete => .delete
  | .update [] => .update none
  | .update names => .update (some (names.filterMap (columnPosition columns)))

/-- The triggers of the catalog that fire for the request, in catalog order. -/
def Catalog.triggersFiring (catalog : Catalog) (request : FireRequest) : List (Nat × CatalogTrigger) :=
  if !request.fire then [] else catalog.zipIdx.filterMap fun (object, position) => match object.entry with
    | .trigger trigger => match catalog.findTable trigger.table with
      | some (table, shape) =>
        if table == request.table && (triggerEvent shape.columns trigger.event).fires request.event then some (position, trigger)
        else none
      | none => none
    | .table _ | .index _ => none

/-- The triggers of the catalog that fire for the request, in the order in which SQLite prepares
them: the {lit}`BEFORE` triggers, then the {lit}`AFTER` triggers, each newest first. Checked
natively: of two triggers whose bodies name different missing tables, the error names the table
of the newer one. -/
def Catalog.firedTriggers (catalog : Catalog) (request : FireRequest) : List (Nat × CatalogTrigger) :=
  let fired := (catalog.triggersFiring request).reverse
  fired.filter (·.2.time == .before) ++ fired.filter (·.2.time == .after)

/-- The write of a step of a program that a write with the conflict algorithm fires: the step's
own algorithm unless the write has one, as SQLite's {lit}`codeTriggerProgram` chooses it. -/
def Resolved.Step.request (algorithm : Option ConflictAlgorithm) : Resolved.Step → Option FireRequest
  | .insert table _ _ own _ => some { table, event := .insert, algorithm := algorithm <|> own, body := true }
  | .update table assignments _ _ => some { table, event := .update (some (assignments.map (·.1))), algorithm, body := true }
  | .delete table _ _ => some { table, event := .delete, algorithm, body := true }
  | .query .. | .raise .. => none

/-- The foreign-key write of a request ({name}`ForeignKeyWrite`). -/
def FireRequest.write (catalog : Catalog) (request : FireRequest) : ForeignKeyWrite :=
  let shape := catalog.tableAt request.table
  match request.event with
  | .insert => .insert true (shape.any fun shape => (catalog.writePolicy request.table shape request.algorithm).keys.contains .replace)
  | .delete => .delete
  | .update set => .update ((shape.map (·.changedColumns (set.getD []))).getD [])

/-- The writes of the actions of the foreign keys of a request, which a request runs with foreign
keys on, besides its programs; their programs inherit ABORT. -/
def FireRequest.keyRequests (catalog : Catalog) (links : List ForeignKeyLink) (request : FireRequest) : List FireRequest :=
  (actionWrites catalog links request.table (request.write catalog)).map fun (child, action) => match action with
    | .update changed => { table := child, event := .update (some changed), algorithm := some .abort }
    | .delete | .insert .. => { table := child, event := .delete, algorithm := some .abort }

/-- Whether the request is an INSERT or an UPDATE that may delete rows by REPLACE: a key of its
policy ({name}`Catalog.writePolicy`) has the algorithm REPLACE. -/
def FireRequest.mayReplace (catalog : Catalog) (request : FireRequest) : Bool :=
  !(request.event matches .delete) && (catalog.tableAt request.table).any fun shape =>
    (catalog.writePolicy request.table shape request.algorithm).keys.contains .replace

/-- The DELETE of the rows that a request may delete by REPLACE ({name}`FireRequest.mayReplace`):
with recursive triggers on, a DELETE that fires the triggers of the table, whose programs
inherit REPLACE, as SQLite's {lit}`sqlite3GenerateConstraintChecks` gives REPLACE to the delete
of the row; with them off and foreign keys on, for an INSERT, a DELETE that fires no trigger,
for the actions of its keys; else none. -/
def FireRequest.replaceRequests (catalog : Catalog) (keys recursive : Bool) (request : FireRequest) :
    List FireRequest :=
  if !request.mayReplace catalog then []
  else if recursive then [{ table := request.table, event := .delete, algorithm := some .replace }]
  else if keys && request.event == .insert then [{ table := request.table, event := .delete, fire := false }]
  else []

/-- The writes that a request runs besides its programs: with foreign keys on, its
{name}`FireRequest.keyRequests`, and its {name}`FireRequest.replaceRequests`. -/
def FireRequest.followUps (catalog : Catalog) (keys recursive : Bool) (request : FireRequest) : List FireRequest :=
  (if keys then request.keyRequests catalog catalog.foreignKeyLinks else []) ++
    request.replaceRequests catalog keys recursive

/-- Resolve the program of the trigger at the position over the catalog, for a write: its
condition over the trigger's rows, which may not name a subquery or call a function that can fail ({name}`RestrictionKind.triggerForm`), and its body statements in order
({name}`resolveBodyStatement`); the first prepare error stops. -/
def resolveProgram (context : ResolveContext) (catalog : Catalog) (position : Nat) (trigger : CatalogTrigger) :
    Except NodeRestriction (Except PrepareError Resolved.Program) := do
  let some (table, shape) := catalog.findTable trigger.table | pure (.error (.noSuchTable trigger.table))
  let row : TriggerRow := { columns := shape.columns, new := !(trigger.event matches .delete),
                            old := !(trigger.event matches .insert) }
  let condition : Except PrepareError (Option Resolved.Expr) ← match trigger.condition with
    | none => pure (.ok none)
    | some term => match condition [] (resolveOperand context.profile.dqsDml (row.scope 0) {} true term) with
      | .error (.prepare error) =>
        if error == .raiseOutsideTrigger then throw (triggerRestriction .raiseForm) else pure (.error (.expression error))
      | .error (.restriction path kind) => throw { path, kind }
      | .ok resolved =>
        if resolved.any Resolved.Expr.isFallibleCall || resolved.any Resolved.Expr.namesSubquery then
          throw (triggerRestriction .triggerForm)
        else pure (.ok (some resolved))
  match condition with
  | .error error => pure (.error error)
  | .ok condition =>
    let body ← trigger.body.foldlM (fun (steps : Except PrepareError (List Resolved.Step)) statement => match steps with
      | .error error => pure (.error error)
      | .ok steps => (·.map (steps ++ [·])) <$> resolveBodyStatement context catalog row statement) (.ok [])
    pure (body.map fun body => { trigger := position, table, time := trigger.time,
                                  event := triggerEvent shape.columns trigger.event, width := shape.columns.length,
                                  condition, body })

/-- The programs of the closure of the requests, from the programs so far, with fuel for the
requests: each request resolves the triggers that it fires and have no program yet, adds the
writes of their bodies and its {name}`FireRequest.followUps`; a request
of a body checks its foreign keys ({name}`Catalog.foreignKeyIssues`). Requests left past the fuel
are {name}`RestrictionKind.triggerForm`. -/
def triggerClosure (context : ResolveContext) (catalog : Catalog) (keys recursive : Bool) :
    Nat → List FireRequest → List FireRequest → List Resolved.Program →
      Except NodeRestriction (Except PrepareError (List Resolved.Program))
  | 0, _, work, programs => if work.isEmpty then pure (.ok programs) else throw (triggerRestriction .triggerForm)
  | _ + 1, _, [], programs => pure (.ok programs)
  | fuel + 1, seen, request :: rest, programs => do
    if keys && request.body then
      match catalog.foreignKeyIssues request.table (request.write catalog) with
      | .error error => return .error error
      | .ok deferred => if deferred then throw (triggerRestriction .deferredForeignKey)
    let mut programs := programs
    let mut next : List FireRequest := request.followUps catalog keys recursive
    for (position, trigger) in catalog.firedTriggers request do
      let program ← match programs.find? (·.trigger == position) with
        | some program => pure (.ok program)
        | none => resolveProgram context catalog position trigger
      match program with
      | .error error => return .error error
      | .ok program =>
        if !programs.any (·.trigger == position) then programs := programs ++ [program]
        next := next ++ program.body.filterMap (·.request request.algorithm)
    let fresh := next.eraseDups.filter fun item => !seen.contains item && !rest.contains item
    triggerClosure context catalog keys recursive fuel (seen ++ fresh) (rest ++ fresh) programs

end Belay.Sqlite.Model
