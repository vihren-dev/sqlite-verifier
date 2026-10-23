import Belay.Sqlite.Translation.CompoundSelect

set_option doc.verso true

/-! The query mappers tied to each other: an expression may hold a subquery, whose clauses hold
expressions. The functions are {lit}`partial`, as the Python translation's are recursive; each
call goes to a part of the parse tree, whose nodes come before their parents. -/

namespace Belay.Sqlite.Translation

open Belay.Sqlite.Model

mutual
  /-- Map an {lit}`expr` production of a query ({name}`queryExpressionWith`). -/
  partial def queryExpression (tree : SqlTree) (node : ParseNode) : TranslateM (Located Syntax.Expr) :=
    queryExpressionWith ⟨queryExpression, queryClauses⟩ tree node

  /-- Map the clauses of a {lit}`select` production ({name}`queryClausesWith`). -/
  partial def queryClauses (tree : SqlTree) (node : ParseNode) : TranslateM Clauses :=
    queryClausesWith ⟨queryExpression, queryClauses⟩ tree node
end

/-- The query mappers of the translation. -/
def queryMappers : Mappers := ⟨queryExpression, queryClauses⟩

end Belay.Sqlite.Translation
