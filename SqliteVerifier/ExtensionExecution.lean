import SqliteVerifier.SqlExecution

/-! The original extension helpers remain useful only under an explicit syntax
guard. They cannot prove transaction or DML behavior through legacy invalid errors. -/
namespace SqliteVerifier

/-- An extension performs exactly the original primitive transition. -/
theorem advance_extension (supported : statement.isExtension = true) :
    advance position statement { database := database } =
      match step statement database position with
      | .success result => .next { database := result }
      | outcome => .halt outcome := by
  cases statement <;> simp_all [Statement.isExtension, advance, literalStep, SqlState.finish]
  all_goals rfl

/-- Legacy autocommit computation agrees only for an entirely additive script. -/
theorem runSqlFrom_extensions (supported : script.all Statement.isExtension = true) :
    runSqlFrom position script { database := database } = runFrom position script database := by
  induction script generalizing position database with
  | nil => rfl
  | cons statement rest ih =>
    simp only [List.all_cons, Bool.and_eq_true] at supported
    rw [runSqlFrom, advance_extension supported.1]
    cases executed : step statement database position <;>
      simp [runFrom, executed, ih supported.2]

/-- Syntax-restricted extension scripts require no additional stored-value domain. -/
theorem supportedSqlFrom_extensions (supported : script.all Statement.isExtension = true) :
    supportedSqlFrom position script { database := database } = true := by
  induction script generalizing position database with
  | nil => rfl
  | cons statement rest ih =>
    simp only [List.all_cons, Bool.and_eq_true] at supported
    have ready : statementReady statement database = true := by
      cases statement <;> simp_all [Statement.isExtension, statementReady]
    rw [supportedSqlFrom, ready, advance_extension supported.1]
    cases step statement database position <;> simp [ih supported.2]

/-- Legacy extension proofs enter the public semantics only with the checked guard. -/
theorem ProfileExecutes.extensions (supported : script.all Statement.isExtension = true)
    (execution : Executes 0 script database outcome) :
    ProfileExecutes profile script database outcome := by
  have same : runSql script database = outcome :=
    (runSqlFrom_extensions supported).trans execution.result
  rw [← same]
  exact .evaluated

end SqliteVerifier
