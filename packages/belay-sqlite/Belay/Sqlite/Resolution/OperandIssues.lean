import Belay.Sqlite.Resolution.IssueLemmas

set_option doc.verso true

/-! The issues of query expression resolution name no catalog object (ADR 0012,
slice 3a). Constant values in writes are resolved as query expressions, and the
rules for prepare errors of INSERT and UPDATE need this fact. -/

namespace Belay.Sqlite

/-- For every literal text and sign, the issues of {name}`queryNumeric` name no
catalog object: the only prepare error is {lit}`hex literal too big`. Proof sketch:
split the match of {name}`queryNumeric`; the failing branches give that error. -/
theorem queryNumeric_issues (text : String) (negated : Bool) : IssuesNameNoObject (queryNumeric text negated) := by
  intro issue failed
  unfold queryNumeric at failed
  dsimp only at failed
  split at failed <;> cases failed <;> simp [ValueIssue.namesNoObject, PrepareError.namesObject]

/-- For every flag and name, the issues of a function call name no catalog object:
{name}`aggregateIssue`, {name}`callIssue` and {name}`pairIssue` give only
{lit}`misuse of aggregate function`, {lit}`wrong number of arguments`, or a restriction.
Proof sketch: unfold the three functions and split their conditions. -/
theorem callIssues (misuse : Bool) (name : String) :
    (aggregateIssue misuse name).namesNoObject ∧ (callIssue name).namesNoObject ∧ (pairIssue name).namesNoObject := by
  unfold aggregateIssue callIssue pairIssue unmodeledFunction
  refine ⟨?_, ?_, ?_⟩ <;> split <;> simp [ValueIssue.namesNoObject, PrepareError.namesObject]

/-- For every name, JSON function and argument list, the issues of {name}`jsonCall` name
no catalog object: its only error is {name}`PrepareError.wrongArgumentCount`. -/
theorem jsonCall_issues (name : String) (function : Resolved.JsonFunction) (arguments : Resolved.Arguments) :
    IssuesNameNoObject (jsonCall name function arguments) := by
  intro issue failed
  unfold jsonCall at failed
  split at failed <;> cases failed
  simp [ValueIssue.namesNoObject, PrepareError.namesObject]

/-- For every date and time function and argument list, the issues of {name}`dateCall`
name no catalog object: it has none. Proof sketch: {name}`dateCall` always succeeds. -/
theorem dateCall_issues (function : Resolved.DateFunction) (arguments : Resolved.Arguments) :
    IssuesNameNoObject (dateCall function arguments) := by
  intro issue failed
  cases failed

/-- For every misuse flag, name and resolved operands, the issues of {name}`pairCall`
with the issue {name}`pairIssue` name no catalog object. Proof sketch: its errors are that
issue, which {name}`callIssues` covers, and those of {name}`jsonCall_issues` and
{name}`dateCall_issues`. -/
theorem pairCall_issues (misuse : Bool) (name : String) (first rest : Resolved.Expr) :
    IssuesNameNoObject (pairCall name first rest (pairIssue name)) := by
  intro issue failed
  unfold pairCall at failed
  dsimp only at failed
  split at failed
  · cases failed
  · split at failed
    · exact jsonCall_issues name _ _ issue failed
    · exact dateCall_issues _ _ issue failed
    · cases failed; exact (callIssues misuse name).2.2

/-- For every setting, column list, flag and expression, the issues of
{name}`resolveOperand` name no catalog object. Proof sketch: induction on the
expression. A compound expression sequences its operands with {name}`bind_issues`,
{name}`under_issues` and {name}`condition_issues`, and fails itself only with a
restriction; a leaf gives {lit}`no such column`, {lit}`ambiguous column name`, a restriction,
{name}`queryNumeric_issues`, {name}`callIssues` or {name}`dateCall_issues`. -/
theorem resolveOperand_issue (dqs : Bool) (scope : Scope) (misuse : Bool)
    (expression : Syntax.Expr) : IssuesNameNoObject (resolveOperand dqs scope misuse expression) := by
  have pair_match : ∀ (a b : Operand) (build : Resolved.Expr → Resolved.Expr → Resolved.Expr)
      (shift : List Nat → List Nat), IssuesNameNoObject (match affinityIssue a b with
        | some (path, reason) => (Except.error (.restriction (shift path) reason) : Except ValueIssue Operand)
        | none => .ok (build a.1 b.1, none)) := by
    intro a b build shift issue failed
    split at failed <;> cases failed; trivial
  induction expression with
  | null | string _ | blob _ | currentTime _ =>
    intro issue failed; simp only [resolveOperand] at failed; cases failed <;> trivial
  | numeric text => exact map_issues _ (queryNumeric_issues _ _)
  | identifier name doubleQuoted =>
    intro issue failed
    simp only [resolveOperand] at failed
    repeat' split at failed
    all_goals (cases failed <;> simp [ValueIssue.namesNoObject, PrepareError.namesObject])
  | qualified source column =>
    intro issue failed
    simp only [resolveOperand] at failed
    repeat' split at failed
    all_goals (cases failed <;> simp [ValueIssue.namesNoObject, PrepareError.namesObject])
  | callStar name =>
    intro issue failed
    simp only [resolveOperand] at failed
    cases failed
    split
    · exact (callIssues misuse name).1
    · exact (callIssues misuse name).2.1
  | call name operand ih =>
    intro issue failed
    simp only [resolveOperand] at failed
    split at failed
    · exact bind_issues (under_issues _ ih) (fun _ => jsonCall_issues name _ _) issue failed
    · split at failed
      · exact bind_issues (under_issues _ ih) (fun _ => dateCall_issues _ _) issue failed
      · cases failed
        split
        · exact (callIssues misuse name).1
        · exact (callIssues misuse name).2.1
  | callEmpty name =>
    intro issue failed
    simp only [resolveOperand] at failed
    split at failed
    · exact dateCall_issues _ _ issue failed
    · cases failed; exact (callIssues misuse name).2.1
  | equals left right ihl ihr =>
    exact bind_issues (under_issues _ ihl) fun a => bind_issues (under_issues _ ihr) fun b =>
      pair_match a b (Resolved.Expr.compare .eq) id
  | compare operator left right ihl ihr =>
    exact bind_issues (under_issues _ ihl) fun a => bind_issues (under_issues _ ihr) fun b =>
      pair_match a b (Resolved.Expr.compare operator) (List.map (· + 1))
  | and left right ihl ihr =>
    exact bind_issues (condition_issues _ ihl) fun _ => bind_issues (condition_issues _ ihr) fun _ =>
      fun _ failed => by cases failed
  | or left right ihl ihr =>
    exact bind_issues (condition_issues _ ihl) fun _ => bind_issues (condition_issues _ ihr) fun _ =>
      fun _ failed => by cases failed
  | not operand ih => exact bind_issues (condition_issues _ ih) fun _ _ failed => by cases failed
  | isNull operand negated ih => exact bind_issues (under_issues _ ih) fun _ _ failed => by cases failed
  | arithmetic operator left right ihl ihr =>
    exact bind_issues (under_issues _ ihl) fun _ => bind_issues (under_issues _ ihr) fun _ _ failed => by cases failed
  | cast operand typeName ih => exact bind_issues (under_issues _ ih) fun _ _ failed => by cases failed
  | positive operand ih => exact bind_issues (under_issues _ ih) fun _ _ failed => by cases failed
  | callPair name first rest ihf ihr =>
    intro issue failed
    simp only [resolveOperand] at failed
    split at failed
    · exact bind_issues (under_issues _ ihf) (fun _ => bind_issues (under_issues _ ihr) fun _ =>
        pairCall_issues misuse name _ _) issue failed
    · cases failed; exact (callIssues misuse name).2.2
  | more first rest ihf ihr =>
    exact bind_issues (under_issues _ ihf) fun _ => bind_issues (under_issues _ ihr) fun _ _ failed => by
      cases failed
  | negate operand ih =>
    cases operand with
    | numeric text => exact map_issues _ (queryNumeric_issues _ _)
    | _ => exact bind_issues (under_issues _ ih) fun _ _ failed => by cases failed

/-- For every list of computations whose issues name no catalog object, the issues of
their concatenation in order name none. Proof sketch: induction on the list, with
{name}`bind_issues` at each element. -/
theorem concat_issues (results : List (Except ValueIssue (List β)))
    (each : ∀ result ∈ results, IssuesNameNoObject result) :
    IssuesNameNoObject (results.foldr (fun next rest => do let first ← next; let others ← rest; .ok (first ++ others))
      (.ok [])) := by
  induction results with
  | nil => intro issue failed; cases failed
  | cons head tail ih =>
    exact bind_issues (each head (by simp)) fun _ =>
      bind_issues (ih fun result member => each result (by simp [member])) fun _ _ failed => by cases failed

/-- For every scope, the issues of one {lit}`RETURNING` column name no catalog
object. Proof sketch: {lit}`source.*` is {name}`PrepareError.returningSourceStar`, which
names none, and an expression has the issues of {name}`resolveOperand` under a path. -/
theorem returningColumn_issues (dqs : Bool) (scope : Scope) (item : Nat)
    (column : Syntax.ResultColumn) : IssuesNameNoObject (returningColumn dqs scope item column) := by
  cases column with
  | star => intro issue failed; cases failed
  | sourceStar source =>
    intro issue failed; cases failed; simp [ValueIssue.namesNoObject, PrepareError.namesObject]
  | expression value alias text =>
    simp only [returningColumn]
    exact bind_issues (under_issues _ (resolveOperand_issue _ _ _ _)) fun operand _ failed => by
      obtain ⟨_, _⟩ := operand; cases failed

/-- For every list of {lit}`RETURNING` columns, the issues of
{name}`resolveReturning` name no catalog object. Proof sketch: a {lit}`source.*` column
gives {name}`PrepareError.returningSourceStar`, which names none; otherwise
{name}`concat_issues` with {name}`returningColumn_issues` for each column. -/
theorem resolveReturning_issue (dqs : Bool) (scope : Scope) (items : List Syntax.ResultColumn) :
    IssuesNameNoObject (resolveReturning dqs scope items) := by
  unfold resolveReturning
  split
  · intro issue failed; cases failed; simp [ValueIssue.namesNoObject, PrepareError.namesObject]
  apply concat_issues
  intro result member
  obtain ⟨index, bound, equal⟩ := List.mem_mapIdx.1 member
  exact equal ▸ returningColumn_issues _ _ _ _

end Belay.Sqlite
