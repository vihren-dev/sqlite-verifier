# ADR 0003 trust extension (deferred design)

Status: deferred design, not a current requirement. Moved out of
[ADR 0003](adr-0003-agent-proof-preparation.md) on 2026-09-29, when the owner
made latency the immediate goal and postponed adversarial acceptance. The
verifier currently assumes trusted execution ([trust boundary](trust-boundary.md)).

This page keeps the adversarial-acceptance analysis written on 2026-09-28 so the
later trust milestone starts from it. It is lightly edited: the latency milestone
now covers the data path itself, and this page lists only what must be added when
agents or their outputs are treated as hostile. Re-check every external claim
(Lean versions, comparator/lean4export behavior) before relying on it.

## Why the data path matters for trust

Compilation runs tactics and other Lean programs, which can perform I/O. Accepting
exported declarations instead of source removes intentional candidate execution
from acceptance: the checker decodes data, replays it in the kernel and compares
it with trusted declarations. This is the design Lean's proof-validation guidance
and comparator describe.

It does not make acceptance safe by itself:

- The current gate imports `.olean` files. Lean's loader assumes structurally
  valid files; turning off initializers does not validate arbitrary serialized
  memory. Candidate `.olean` files must never be accepted from untrusted agents.
  Untrusted compile-time code can also try to manufacture malicious output bytes.
- Official Lean 4.34.0 release notes describe soundness fixes relevant to crafted
  proofs. Regression success is not evidence that the 4.33.0 pin is adequate for
  hostile submissions. No exploit against this repository was demonstrated.
- Checking a Lean proof still type-checks and reduces terms: it needs decoding,
  size, memory and time budgets, and it is not succinct verification.

## What the trust milestone adds

### Authority over the approved contract

The optional [baseline check](../migration_check/baseline.py) binds approved
source bytes and dependencies; it does not authenticate a human. A correct source
hash attached to agent-produced declarations does not show they came from that
source. Approved interpretations may import generated `SchemaInputs`, so an
elaborated contract depends on the starting schema.

Add a trusted registration step. An administrative build prepares a review bundle
(approved source closure, hashes, elaborated declarations and a readable account of
the logical state, predicates, current interpretation and assumptions). The
trusted process validates the export format and replays approved declarations
against the pinned library and independently constructed schema definitions. The
approved closure may depend on those roots but not on migration-dependent SQL or
candidate definitions. After explicit human review, an authorized operator
publishes an immutable record that agents cannot modify, binding the declaration
payload, source provenance, starting-schema SQL hash, SQLite profile, formal
library, axiom policy, checker/export versions and named roots. V1 binds one
concrete starting schema.

Use a versioned, domain-separated SHA-256 identity over a canonical manifest and
the payload digest; the registry maps identities to authorized records, and hashing
alone grants no authority. The trusted caller chooses the expected contract ID; a
bundle cannot select an easier approved contract. Verification snapshots one
active record; revocation affects later requests.

### Bounded, validated decoding

Accept one framed bundle file: format magic/version, bounded manifest and payload
lengths, then manifest and proof bytes. No field selects executables, files,
import paths, network locations or checker configuration. The decoder validates
framing, lengths, encodings, record tags, reference bounds, expression structure,
declaration uniqueness and supported declaration groups before building kernel
objects; unknown records and versions fail closed. Reject duplicate JSON keys,
trailing data, malformed references and cycles where the format requires a DAG.

Exported declarations that repeat protected ones must match complete records
(bodies, universes, safety flags, constructors, recursors) after the exporter's
normalization; names or types alone are insufficient. Reject extra candidate
declarations outside the proof, interpretation and target closure, except required
members of mutual/inductive groups. Enforce the axiom/unsafe/partial policy on
every proof and target dependency.

### Independent kernel

Qualify [Nanoda](https://github.com/ammkrn/nanoda_lib) (or another independent
checker) on the exported data so acceptance does not rest on one kernel. Replaying
into an empty environment exposes comparator issue
[#93](https://github.com/leanprover/comparator/issues/93) (string-literal
reduction); check both kernels on string-heavy proofs early.
ADR 0004 (model conformance validation, draft not yet published) tier 3 depends on this.

### Deployment authority

The verifier installation, registry, runtime library and result channel must be
inaccessible to agents. Separate commands under one unrestricted account do not
enforce this; a service or CI deployment must show the actual permission boundary.
Containment of preparation and of the checker process belongs to the caller or an
integration layer, not to the verifier core.

## Additional acceptance cases for this milestone

| Family | Required evidence |
| --- | --- |
| Contract authority | Unknown, inactive or wrong expected ID fails; a self-consistent agent manifest cannot register a weaker contract or replace protected definitions |
| Registration fidelity | Same source hash with different compiled declarations cannot replace an authorized record; a schema-dependent interpretation cannot reuse another schema's registration |
| Malformed evidence | Truncation, oversized lengths, duplicate keys/names, invalid references, expression cycles, unknown tags, bad encodings and native/plugin records fail within budgets |
| Snapshot/permissions | Concurrent changes cannot swap checked bytes; an agent cannot change registry, checker or library or forge the result channel |
| Independent kernel | Every existing positive and refutation case is accepted by both kernels; injected kernel-visible defects are rejected by both |

Rollback disables bundle acceptance without redirecting hostile bundles into
`.olean` import and without treating rollback as a fix for checker issues.

## References

- [Lean: validating proofs, hostile module files, and comparator](https://lean-lang.org/doc/reference/latest/ValidatingProofs/)
- [Lean 4.34.0 soundness fixes](https://lean-lang.org/doc/reference/latest/releases/v4.34.0/)
- [Comparator](https://github.com/leanprover/comparator), [lean4export](https://github.com/leanprover/lean4export)
