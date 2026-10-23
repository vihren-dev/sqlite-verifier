import Belay.Sqlite.Model.Declarations

set_option doc.verso true

/-! The rows of a pragma as a source of {lit}`FROM` (ADR 0019, D2). A pragma statement is a
query over such a source, and so are the table-valued forms {lit}`pragma_table_info('t')` and
{lit}`pragma_foreign_key_list('t')`, so that both forms have one meaning. -/

namespace Belay.Sqlite.Model.Resolved

/-- The rows of a pragma. For example, {lean}`PragmaRows.fixed 1 [[.integer 1]]` is the row of
{lit}`PRAGMA foreign_keys` with foreign keys on. -/
inductive PragmaRows where
  /-- Rows that resolution computes from the catalog, each with {lit}`width` cells: the rows
  of {lit}`PRAGMA table_info`, of {lit}`PRAGMA foreign_key_list` and of the query of a
  setting. -/
  | fixed (width : Nat) (rows : List (List Value))
  /-- The rows of {lit}`PRAGMA integrity_check` or, with {lit}`quick`, of
  {lit}`PRAGMA quick_check`, which the run computes from the stored rows: at most {lit}`limit`
  rows (100 for 0), for the table at the catalog position {lit}`table`, or for every table with
  {lean}`(none : Option Nat)`. Each row has one cell. -/
  | check (quick : Bool) (limit : Nat) (table : Option Nat)
  /-- The rows of {lit}`PRAGMA foreign_key_check`, which the run computes from the stored rows:
  for the table at the catalog position {lit}`table`, or for every table with
  {lean}`(none : Option Nat)`. Each row has four cells. -/
  | foreignKeyCheck (table : Option Nat)
  deriving Repr, DecidableEq

/-- The number of cells of each row of the pragma. -/
def PragmaRows.width : PragmaRows → Nat
  | .fixed width _ => width
  | .check .. => 1
  | .foreignKeyCheck _ => 4

end Belay.Sqlite.Model.Resolved
