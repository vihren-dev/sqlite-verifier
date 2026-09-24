# What a result establishes

`VERIFIED` means a closed proof of the reconstructed `VerificationConditions`
passed Lean kernel replay and the foundational-axiom policy. The contract includes
a nonempty admitted-start witness, sound current/result/failure representations,
starting validity, explicit applicability, and obligations for every inductive
execution outcome. A theorem with an additional unproved premise cannot satisfy
this target. `Q` need not be globally reflexive or transitive.

`VIOLATED` means a closed, audited proof of the negation of that same model
contract. It does not imply a native replay occurred. Compiler failures, missing
proofs, exhausted resources, and unfinished proofs are `UNVERIFIED`.

The trusted implementation includes the installed Python driver, pinned SQLite
tokenizer/grammar adapter, CST admission and SQL-to-Lean emitter, source staging,
Lean runtime/kernel and serialized-module loader, protected proof library,
process isolation, and native/model correspondence assumptions. The caller must
protect that installation, its runtime paths/environment, approved source files,
and any approval baseline. Candidate Lean source can execute tactics; ordinary
project compilation is therefore neither a sufficient proof gate nor safe input
handling. The launcher uses Python's isolated mode and never loads a caller's
Lake configuration or precompiled Lean artifacts.

[Source staging](source-staging.md) snapshots reachable imports, prevents candidate
sources from entering approved compilation, and seals generated SQL independently.
Each compiler process has only read-only declared inputs and its own writable
scratch directory, with no host network/credentials, bounded time and output.
The kernel checker separately receives sealed inputs. macOS uses Seatbelt;
Linux uses bubblewrap user/mount/PID/network namespaces. These are OS boundaries,
not virtual machines. Limits bound each produced file and captured stream, not
the total disk footprint of every possible tactic.

[The kernel gate](kernel-gate.md) compares protected declaration contents,
replays actual bodies, reconstructs the expected proposition independently of the
candidate's convenience alias, and traverses actual transitive dependencies.
Allowed axioms are only `propext`, `Classical.choice`, and `Quot.sound`.
Candidate initializers and serialized axiom caches do not establish acceptance.

The public interpretation interface permits arbitrary logical state and predicates.
Its type signature alone cannot certify that every arbitrary custom reader obtains
its answer from storage; a constant reader is still expressible. Human review of
approved meaning and coverage remains essential. Current additive execution
primitives independently preserve every existing physical row and cell, and the
provided projection helpers prove coverage while reading resulting storage.
Future destructive/storage-rebuilding support needs stronger provenance obligations
before making equivalent guarantees. The present release makes no such claim.

The engineering examples and their baselines are demonstrations. They do not
constitute product-owner approval of another application's logical requirements.
Real pilot acceptance and human effort measurements remain separate milestones.
