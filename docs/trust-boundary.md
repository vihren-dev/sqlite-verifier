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
and native/model correspondence assumptions. The caller must
protect that installation, its runtime paths/environment, approved source files,
and any approval baseline. Lean source can execute arbitrary code during compilation. The current CLI assumes
trusted execution: callers must trust that code and protect approved inputs, the
verifier process and its result channel. It provides no OS sandbox, network
restriction or filesystem containment. Kernel replay rejects invalid proofs but
does not protect a checker environment that executable source can modify.

[Source staging](source-staging.md) snapshots reachable imports, separates approved
and candidate module search paths, and generates SQL inputs independently. These
are logical compilation boundaries, not OS access controls. Processes use explicit
environments, separate scratch directories, deadlines and bounded output. The
launcher uses Python's isolated import mode; that is not a security sandbox.

Hostile-input containment is deferred to a future integration layer after the
preparation/checking separation proposed in ADR-003. A single outer container can
protect the host without protecting approved inputs from other processes inside
it; the integration must establish the latter boundary too.

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
