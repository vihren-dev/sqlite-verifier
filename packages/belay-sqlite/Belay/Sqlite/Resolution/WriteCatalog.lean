import Belay.Sqlite.Resolution.Resolve

set_option doc.verso true

/-! Writes leave the catalog unchanged: a successful resolution of INSERT, UPDATE or
DELETE returns the input catalog. {lit}`NamesSpec` uses these lemmas for the
unique-names rule. -/

namespace Belay.Sqlite

/-- For every successful resolution of INSERT, the catalog is unchanged. Proof sketch:
every branch of the resolver returns the input catalog. -/
theorem resolveInsert_same (context : ResolveContext) (catalog after : Catalog) (index : Nat)
    (tableName : String) (names : Option (List String)) (rows : List (List Syntax.Expr))
    (conflicts : List Syntax.ConflictClause) (algorithm : Option ConflictAlgorithm)
    (returning : List Syntax.ResultColumn)
    (statement : Resolved.Statement)
    (ok : resolveInsert context catalog index tableName names rows conflicts algorithm returning = .ok (statement, after)) :
    after = catalog := by
  unfold resolveInsert at ok
  simp only [prepareError, restrict, issueResolution] at ok
  repeat' split at ok
  all_goals first | (cases ok; rfl) | (cases ok)

/-- For every successful resolution of UPDATE, the catalog is unchanged. Proof sketch:
every branch of the resolver returns the input catalog. -/
theorem resolveUpdate_same (context : ResolveContext) (catalog after : Catalog) (index : Nat)
    (tableName : String) (assignments : List (String × Syntax.Expr)) (filter : Option Syntax.Expr)
    (returning : List Syntax.ResultColumn)
    (statement : Resolved.Statement)
    (ok : resolveUpdate context catalog index tableName assignments filter returning = .ok (statement, after)) :
    after = catalog := by
  unfold resolveUpdate at ok
  simp only [prepareError, restrict, issueResolution] at ok
  repeat' split at ok
  all_goals first | (cases ok; rfl) | (cases ok)

/-- For every successful resolution of DELETE, the catalog is unchanged. Proof sketch:
every branch of the resolver returns the input catalog. -/
theorem resolveDelete_same (context : ResolveContext) (catalog after : Catalog) (index : Nat)
    (tableName : String) (filter : Option Syntax.Expr) (returning : List Syntax.ResultColumn)
    (statement : Resolved.Statement)
    (ok : resolveDelete context catalog index tableName filter returning = .ok (statement, after)) :
    after = catalog := by
  unfold resolveDelete at ok
  simp only [prepareError, restrict, issueResolution] at ok
  repeat' split at ok
  all_goals first | (cases ok; rfl) | (cases ok)

end Belay.Sqlite
