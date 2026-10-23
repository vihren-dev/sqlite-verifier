import Belay.Sqlite.Model.Resolution.Messages

set_option doc.verso true

/-! The name that a prepare error is about, so that a tool can show the error at that name in
the SQL text. A prepare error has no path to a node, as a model restriction has; it has only the
names in its message. -/

namespace Belay.Sqlite.Model

/-- The name in the message of the error that the text of the statement writes, or
{lean}`(none : Option Identifier)` when the message has no such name. A qualified column
is one name with a dot, as {name}`ExprError.noSuchColumn` keeps it. For example
{assert}`(ExprError.tableHasNoColumn (name! "t") (name! "zz")).name? = some (name! "zz")`.
A name with a schema, such as {lit}`main.t.a` in {lit}`ambiguous column name: main.t.a`, is one
name with two dots, which the text seldom writes, so a tool then shows the error at the
statement. A function name is the name as written, and so is the text of a hexadecimal
literal. -/
def ExprError.name? : ExprError → Option Identifier
  | .reservedName name | .tooManyColumns name | .duplicateColumn name | .multiplePrimaryKeys name
  | .defaultNotConstant name | .tableHasNoColumn _ name | .valueCount name _ _
  | .tableMayNotBeAltered name | .tableMayNotBeIndexed name | .primaryKeyMissing name
  | .noSuchColumn name | .noSuchCollation name | .foreignKeyOneColumn name _
  | .unknownForeignKeyColumn name | .insertGenerated name | .updateGenerated name
  | .errorInGenerated name | .unknownDatatype _ name _ | .missingDatatype _ name
  | .ambiguousColumn name | .noSuchSource name | .joinUsingColumn name
  | .ambiguousUsingReference name => some name
  | .hexLiteralTooBig text | .misuseOfAggregate text | .wrongArgumentCount text
  | .noSuchFunction text => some (Identifier.ofString text)
  | .valuesForColumns _ _ | .valuesDiffer | .cannotAddPrimaryKey | .cannotAddUnique
  | .conflictingAlgorithms | .foreignKeyColumnCount | .generatedInPrimaryKey | .defaultOnGenerated
  | .nondeterministicGenerated | .onlyGeneratedColumns | .qualifiedGenerated | .qualifiedIndexTerm
  | .nondeterministicIndex _ | .aggregateInGroupBy | .orderByOutOfRange _ _ | .groupByOutOfRange _ _
  | .likelihoodArgument | .tooManyTables | .returningSourceStar | .naturalJoinCondition
  | .conflictTargetMismatch | .noTablesSpecified | .tooManyEachArguments | .subqueryColumns _
  | .havingNonAggregate | .raiseOutsideTrigger | .triggerOnSystemTable | .parameterInCheck
  | .parameterInGenerated | .parameterInIndex _ | .triggerVariables | .compoundColumns _
  | .orderByNoMatch _ => none

/-- The name in the message of the prepare error ({name}`ExprError.name?` for an error that
names no catalog object). For a foreign key mismatch it is the child table, which the write
names. The name can be absent from the statement's text, for example the parent table of a
foreign key; a tool then shows the error at the statement. For example
{assert}`(PrepareError.noSuchTable (name! "u")).name? = some (name! "u")`. -/
def PrepareError.name? : PrepareError → Option Identifier
  | .tableExists name | .indexNameUsed name | .tableNameUsed name | .indexExists name
  | .noSuchTable name | .noSuchIndex name | .tableMayNotBeDropped name
  | .noSuchReferencedTable name | .foreignKeyMismatch name _ | .noSuchTrigger name
  | .triggerExists name => some name
  | .expression error => error.name?

end Belay.Sqlite.Model
