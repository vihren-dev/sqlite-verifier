import Belay.Sqlite.Model.Resolution.WriteResolution
import Belay.Sqlite.Model.Resolution.SelectResolution
import Belay.Sqlite.Model.Resolution.TriggerRaise
import Belay.Sqlite.Model.StatementClock

set_option doc.verso true

/-! Resolution of the statements of a trigger's body (ADR 0018, D5) with the resolvers of the
statements of the same name, over the trigger's rows ({name}`Belay.Sqlite.Model.TriggerRow`). A
restriction of a body is a restriction of the write whose resolution resolves the trigger. A
{lit}`RAISE` that stays in a statement is SQLite's prepare error {lit}`RAISE() may only be used within a trigger-program`
there, and so the restriction of a {lit}`RAISE` form here. -/

namespace Belay.Sqlite.Model

/-- A restriction of a trigger of the write, at the write's statement node. -/
def triggerRestriction (kind : RestrictionKind) : NodeRestriction := { path := [], kind }

/-- The step of a query of a body: a restriction of a trigger form when an expression of it calls
a connection counter ({name}`Resolved.Expr.isCounter`), whose value inside a program the model
does not describe (ADR 0024, D2). -/
def queryStep (step : Resolved.Step) : Except NodeRestriction (Except PrepareError Resolved.Step) :=
  if step.expressions.any (·.any Resolved.Expr.isCounter) then .error (triggerRestriction .triggerForm)
  else .ok (.ok step)

/-- The step of a write of a body: a restriction of a trigger form when an expression of it has a
call that can fail ({name}`Resolved.Expr.isFallibleCall`), whose failure the row engine does not
describe, or a call of a connection counter, as for {name}`queryStep`. -/
def writeStep (step : Resolved.Step) : Except NodeRestriction (Except PrepareError Resolved.Step) :=
  if step.expressions.any (·.any Resolved.Expr.isFallibleCall) then .error (triggerRestriction .triggerForm)
  else queryStep step

/-- The step of a resolved body statement, its prepare error, or a restriction. -/
def bodyStep : StatementResolution → Except NodeRestriction (Except PrepareError Resolved.Step)
  | .error restriction => .error restriction
  | .ok (.prepareError error, _) =>
    if error == .expression .raiseOutsideTrigger then .error (triggerRestriction .raiseForm) else .ok (.error error)
  | .ok (.insert table rows _ subqueries _, _) => writeStep (.insert table rows [] none subqueries)
  | .ok (.upsert table rows clauses _ algorithm subqueries _, _) => writeStep (.insert table rows clauses algorithm subqueries)
  | .ok (.update table assignments filter _ subqueries _, _) => writeStep (.update table assignments filter subqueries)
  | .ok (.delete table filter _ subqueries _, _) => writeStep (.delete table filter subqueries)
  | .ok (.query query subqueries, _) => queryStep (.query query subqueries)
  | .ok (.createTable .., _) | .ok (.createIndex .., _) | .ok (.createTrigger .., _) | .ok (.addColumn .., _)
  | .ok (.drop .., _) | .ok (.begin, _) | .ok (.commit, _) | .ok (.rollback, _) | .ok (.setting .., _) =>
    .error (triggerRestriction .triggerForm)

/-- Resolve a SELECT of a trigger's body as {lit}`resolveSelect` does, with the trigger's rows as
the outer cells of its query, before the cells of its own sources, as a subquery has them. -/
def resolveBodySelect (context : ResolveContext) (catalog : Catalog) (row : TriggerRow)
    (query : Syntax.Subquery) (subqueries : List Syntax.Subquery) : StatementResolution :=
  let dqs := context.profile.dqsDml
  let resolved : Except SourceIssue (Resolved.Query × List Resolved.Query) := do
    let (pending, inner) ← resolveSources catalog query.source query.joins row.width
    let scope := Scope.enclose (row.scope 0) inner
    let main : QueryScope := { scope, pending, outer := row.width, outerAliases := [],
                               aliases := (resultAliases scope query.columns).filterMap id }
    let (resolvedSubqueries, shapes) ← resolveSubqueries dqs catalog 8 main subqueries
    let (resolvedQuery, _) ← (resolveQueryBody dqs scope { later := shapes, outer := row.width } [] pending query).mapError .value
    pure (resolvedQuery, resolvedSubqueries)
  match resolved with
  | .ok (resolvedQuery, resolvedSubqueries) => .ok (.query resolvedQuery resolvedSubqueries, catalog)
  | .error (.noSuchTable name) => prepareError catalog (.noSuchTable name)
  | .error (.value issue) => issueResolution catalog [] issue

/-- Whether a query of a raising SELECT is one that the model evaluates: no source, no
aggregate, no grouping, order, window, {lit}`HAVING` or {lit}`DISTINCT`, no subquery and no call
that can fail, so its one row raises in a known order. -/
def raiseQueryPlain (query : Resolved.Query) (subqueries : List Resolved.Query) : Bool :=
  query.sources.isEmpty && !query.aggregate && query.groupBy.isEmpty && query.orderBy.isEmpty && query.limit.isNone &&
    query.offset == 0 && query.having.isNone && query.distinct.isNone && subqueries.isEmpty &&
    !query.expressions.any (·.any Resolved.Expr.isFallibleCall)

/-- Resolve a SELECT whose one result column raises ({name}`raisingColumn`): the SELECT with the
column whose {lit}`RAISE` results are NULL and a column for each message, which resolves the
messages for their errors; then its filter and the arms of the column. A SELECT of another shape
or a query that the model does not evaluate ({name}`raiseQueryPlain`) is the restriction of a
{lit}`RAISE` form. -/
def resolveRaiseSelect (context : ResolveContext) (catalog : Catalog) (row : TriggerRow)
    (query : Syntax.Subquery) (column : Syntax.Expr) (kinds : List (Option Syntax.RaiseKind))
    (messages : List Syntax.Expr) : Except NodeRestriction (Except PrepareError Resolved.Step) :=
  let extra := messages.map fun message => Syntax.ResultColumn.expression message none ""
  match bodyStep (resolveBodySelect context catalog row
      { query with columns := .expression column none "" :: extra } []) with
  | .error restriction => .error restriction
  | .ok (.error error) => .ok (.error error)
  | .ok (.ok (.query resolved subqueries)) =>
    if !raiseQueryPlain resolved subqueries then .error (triggerRestriction .raiseForm)
    else match resolved.columns.head? with
      | some (.scalar (.scalar .iif arguments)) =>
        let (arms, otherwise) := raiseArms arguments.toList kinds
        .ok (.ok (.raise resolved.filter arms otherwise))
      | some (.scalar _) | some (.aggregate _) | none => .ok (.ok (.raise resolved.filter [] kinds.head?.join))
  | .ok (.ok (.insert ..)) | .ok (.ok (.update ..)) | .ok (.ok (.delete ..)) | .ok (.ok (.raise ..)) =>
    .error (triggerRestriction .triggerForm)

/-- Resolve one statement of a trigger's body over the catalog, with
the trigger's rows: an INSERT around no table, with {lit}`ON CONFLICT DO UPDATE` the restriction
of a trigger form; an UPDATE and a DELETE around the written table; a SELECT whose one result
column raises as {name}`resolveRaiseSelect`, when it has no other clause than {lit}`WHERE`, and
the restriction of a {lit}`RAISE` form when it has one; and another SELECT as
{name}`resolveBodySelect`. -/
def resolveBodyStatement (context : ResolveContext) (catalog : Catalog) (row : TriggerRow) :
    Syntax.BodyStatement → Except NodeRestriction (Except PrepareError Resolved.Step)
  | .insert table columns rows conflicts algorithm subqueries =>
    if conflicts.any (·.action matches .update ..) then .error (triggerRestriction .triggerForm)
    else bodyStep (resolveWriteSubqueries context catalog 6 table (fun _ => row.scope 0) subqueries
      fun resolved shapes => resolveInsert context catalog table columns rows conflicts algorithm [] resolved shapes (some row))
  | .update table assignments filter subqueries =>
    bodyStep (resolveWriteSubqueries context catalog 4 table
      (fun shape => writtenScope table shape ++ row.scope shape.columns.length) subqueries
      fun resolved shapes => resolveUpdate context catalog table assignments filter [] resolved shapes (some row))
  | .delete table filter subqueries =>
    bodyStep (resolveWriteSubqueries context catalog 3 table
      (fun shape => writtenScope table shape ++ row.scope shape.columns.length) subqueries
      fun resolved shapes => resolveDelete context catalog table filter [] resolved shapes (some row))
  | .select columns source joins filter groupBy orderBy limit offset subqueries having distinct =>
    let query : Syntax.Subquery := { columns, source, joins, filter, groupBy, orderBy, limit, offset, parent := none,
                                     having, distinct }
    match columns with
    | [.expression value _ _] => match raisingColumn value with
      | some (column, kinds, messages) =>
        if source.isSome || !joins.isEmpty || !groupBy.isEmpty || !orderBy.isEmpty || limit.isSome || offset.isSome ||
            !subqueries.isEmpty || having.isSome || distinct then .error (triggerRestriction .raiseForm)
        else resolveRaiseSelect context catalog row query column kinds messages
      | none => bodyStep (resolveBodySelect context catalog row query subqueries)
    | [] | [.star] | [.sourceStar _] | _ :: _ :: _ => bodyStep (resolveBodySelect context catalog row query subqueries)

end Belay.Sqlite.Model
