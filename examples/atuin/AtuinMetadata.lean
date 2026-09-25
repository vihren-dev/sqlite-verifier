import NextInterpretation

/-! Ordinary literal INSERT facts over arbitrary accepted old bookkeeping rows. -/
namespace AtuinMetadata
open SqliteVerifier

/-- This SQL example instantiates one clock value, not a live clock dependency. -/
def timestamp : List UInt8 := "2026-09-25 00:00:00".toUTF8.toList
/-- Both explicit writes use the same application row shape. -/
def values (elapsed : Int) : List Value := AtuinCatalog.newValues timestamp elapsed
/-- The ordinary allocator supplies the new physical row identity. -/
def extended (table : Table) (elapsed : Int) : Table := LiteralData.inserted table (values elapsed)

/-- Successful identities expose the actual INTEGER version stored in the first field. -/
theorem identified_version (columns : table.columns = SchemaBinding.metadata.columns)
    (identified : AtuinCatalog.identify row = some identity) :
    LiteralData.read table row "version" = some (.integer identity.1) := by
  unfold AtuinCatalog.identify at identified
  split at identified <;>
    simp_all [LiteralData.read, SchemaBinding.metadata]
  subst identity
  rfl

/-- The six accepted identities do not already contain the pending target. -/
theorem target_absent (columns : table.columns = SchemaBinding.metadata.columns)
    (recorded : AtuinCatalog.recorded AtuinCatalog.prior table.rows) :
    ∀ row ∈ table.rows, LiteralData.read table row "version" ≠ some (.integer AtuinCatalog.targetVersion) := by
  intro row member equal
  have known := recorded.mem_iff.mp (List.mem_map.mpr ⟨row, member, rfl⟩)
  obtain ⟨identity, prior, identified⟩ := List.mem_map.mp known
  have read := identified_version columns identified.symm
  have version : identity.1 = AtuinCatalog.targetVersion := by simpa [equal] using read.symm
  have absent : AtuinCatalog.targetVersion ∉ AtuinCatalog.prior.map Prod.fst := by decide +kernel
  exact absent (List.mem_map.mpr ⟨identity, prior, version⟩)

/-- The inserted version is a stored integer, independently of the allocated rowid. -/
theorem new_version (columns : table.columns = SchemaBinding.metadata.columns) :
    LiteralData.read table { rowid := rowid, values := values elapsed } "version" =
      some (.integer AtuinCatalog.targetVersion) := by
  simp only [LiteralData.read, columns]
  rfl

/-- A pending target cannot collide with any accepted old unique version. -/
theorem fresh_key (columns : table.columns = SchemaBinding.metadata.columns)
    (recorded : AtuinCatalog.recorded AtuinCatalog.prior table.rows) (member : row ∈ table.rows) :
    LiteralData.keyEqual table ["version"] row { rowid := rowid, values := values elapsed } = false := by
  have absent := target_absent columns recorded row member
  simp only [LiteralData.keyEqual, List.all_cons, List.all_nil, Bool.and_true, new_version columns]
  generalize LiteralData.read table row "version" = observed at absent ⊢
  cases observed with
  | none => rfl
  | some value => cases value <;> simp_all

/-- Literal values satisfy NOT NULL and the target is distinct from all previous keys. -/
theorem extended_constraints (columns : table.columns = SchemaBinding.metadata.columns)
    (properties : table.properties = SchemaBinding.metadata.properties)
    (invariant : AtuinCatalog.Invariant AtuinCatalog.prior table) :
    LiteralData.constraints (extended table elapsed) = true := by
  have old : LiteralData.constraints table = true := by
    have both := invariant.1
    simp only [LiteralData.tableReady, Bool.and_eq_true] at both
    exact both.2
  apply LiteralData.inserted_constraints old
  · rw [columns]
    rfl
  · intro key member row stored
    have keys : table.properties.keys = [["version"]] := by rw [properties]; rfl
    have only : key = ["version"] := by simpa [keys] using member
    subst key
    exact fresh_key columns invariant.2 stored

/-- Successful identities append exactly once; no old malformed record can be filtered out. -/
theorem extended_recorded (recorded : AtuinCatalog.recorded AtuinCatalog.prior table.rows) :
    AtuinCatalog.recorded (AtuinCatalog.prior ++ [AtuinCatalog.target]) (extended table elapsed).rows := by
  simpa [AtuinCatalog.recorded, extended, LiteralData.inserted, AtuinCatalog.identify,
    values, AtuinCatalog.newValues, AtuinCatalog.target] using recorded.append_right [some AtuinCatalog.target]

/-- INSERT retains the generic comparison domain and the actual seven-identity invariant. -/
theorem extended_invariant (columns : table.columns = SchemaBinding.metadata.columns)
    (properties : table.properties = SchemaBinding.metadata.properties)
    (invariant : AtuinCatalog.Invariant AtuinCatalog.prior table) :
    AtuinCatalog.Invariant (AtuinCatalog.prior ++ [AtuinCatalog.target]) (extended table elapsed) := by
  refine ⟨?_, extended_recorded invariant.2⟩
  have keys : table.properties.keys = [["version"]] := by rw [properties]; rfl
  have ready : LiteralData.comparisonReady table "version" = true := by
    have both := invariant.1
    simp only [LiteralData.tableReady, Bool.and_eq_true] at both
    simpa [keys] using both.1
  have inserted := LiteralData.inserted_comparison ready (values := values elapsed) (by
    rw [new_version columns]
    decide +kernel)
  simp only [LiteralData.tableReady, Bool.and_eq_true]
  refine ⟨?_, extended_constraints columns properties invariant⟩
  change table.properties.keys.all (fun key => key.all
    (LiteralData.comparisonReady (extended table elapsed))) = true
  simpa [keys, extended] using inserted

end AtuinMetadata
