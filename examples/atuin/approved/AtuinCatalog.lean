import SqliteVerifier

/-! Example-only application data facts. These are approved interpretation inputs,
not an execution profile or a framework integration. -/
namespace AtuinCatalog
open SqliteVerifier

/-- A successful bookkeeping identity consists of its version and original SQL checksum. -/
abbrev Identity := Int × List UInt8
/-- The selected shell migration's version, independent of candidate SQL generation. -/
def targetVersion : Int := 20260709214605
/-- SHA-384 of the source-linked original ALTER statement. -/
def targetChecksum : List UInt8 := [83, 118, 187, 61, 220, 106, 153, 86, 101, 43, 255, 43, 152, 7, 182, 74, 131, 33, 154, 66, 1, 209, 241, 231, 222, 159, 119, 96, 242, 80, 127, 25, 24, 86, 174, 95, 84, 154, 118, 19, 37, 61, 18, 132, 201, 161, 185, 136]
/-- The target identity is an application requirement, not a profile instruction. -/
def target : Identity := (targetVersion, targetChecksum)
/-- Exactly the six preceding successful identities in this example's accepted state. -/
def prior : List Identity := [
  (20210422143411, [222, 4, 109, 91, 202, 17, 84, 158, 178, 153, 31, 148, 103, 240, 107, 88, 45, 48, 41, 197, 75, 234, 21, 29, 250, 175, 122, 101, 245, 90, 140, 120, 99, 15, 59, 137, 153, 45, 60, 163, 13, 20, 123, 15, 66, 144, 41, 77]),
  (20220505083406, [85, 79, 93, 184, 38, 120, 20, 150, 72, 104, 156, 205, 202, 234, 211, 250, 111, 124, 138, 236, 130, 46, 142, 75, 171, 29, 8, 3, 9, 197, 161, 162, 47, 10, 4, 210, 176, 204, 28, 197, 43, 177, 165, 157, 27, 80, 20, 236]),
  (20220806155627, [240, 199, 65, 160, 51, 160, 54, 229, 65, 177, 244, 210, 115, 36, 143, 26, 52, 31, 9, 107, 163, 105, 207, 93, 40, 254, 95, 18, 205, 156, 188, 216, 150, 125, 91, 111, 49, 43, 148, 47, 228, 194, 6, 189, 51, 36, 41, 236]),
  (20230315220114, [198, 135, 29, 175, 41, 196, 164, 124, 60, 67, 149, 43, 186, 83, 160, 193, 113, 140, 185, 177, 145, 145, 133, 147, 41, 72, 224, 79, 96, 93, 177, 209, 116, 96, 121, 152, 145, 115, 242, 107, 115, 32, 112, 113, 60, 84, 104, 241]),
  (20230319185725, [92, 241, 213, 67, 80, 199, 49, 197, 118, 90, 248, 37, 14, 27, 95, 22, 220, 16, 86, 55, 169, 81, 219, 215, 239, 253, 92, 35, 211, 105, 94, 140, 61, 148, 66, 250, 67, 117, 35, 71, 132, 215, 211, 216, 199, 104, 157, 147]),
  (20260224000100, [106, 245, 24, 182, 236, 229, 185, 143, 213, 201, 2, 105, 220, 172, 55, 157, 250, 103, 231, 3, 185, 212, 201, 167, 140, 79, 142, 53, 180, 1, 167, 227, 84, 116, 40, 44, 177, 92, 70, 205, 17, 93, 57, 38, 35, 110, 234, 180])]

/-- Invalid or unsuccessful records remain visible as none and cannot be discarded. -/
def identify (row : Row) : Option Identity :=
  match row.values with
  | [.integer version, _, _, .integer 1, .blob checksum, _] => some (version, checksum)
  | _ => none

/-- Complete coverage permits physical enumeration order without omitting bad rows. -/
def recorded (expected : List Identity) (rows : List Row) : Prop :=
  (rows.map identify).Perm (expected.map some)

/-- Key/NN validity and the actual successful identity set are representation invariants. -/
def Invariant (expected : List Identity) (table : Table) : Prop :=
  LiteralData.tableReady table = true ∧ recorded expected table.rows

/-- Timestamp and duration are variable application values, not framework-generated effects. -/
def newValues (timestamp : List UInt8) (elapsed : Int) : List Value :=
  [.integer targetVersion, .text "shell".toUTF8.toList, .text timestamp,
    .integer 1, .blob targetChecksum, .integer elapsed]

end AtuinCatalog
