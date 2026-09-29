# ADR 0003: Separate agent proof preparation from trusted verification

- Status: Proposed
- Date: 2026-09-28
- Implementation examined: `54ea013ab12d16fdc35d9b08bd26078c24c547aa`
- Decision owners: product owner for guarantees and approval workflow; formal
  methods lead for proof acceptance and the trust boundary
- Related: [ADR 0001](adr-0001-pytest-and-nix-ci.md),
  [ADR 0002](adr-0002-compile-project-cache.md)
- If accepted: replaces ADR 0002's proposed runtime compilation-cache design;
  preserves its useful timing work. This proposal does not itself change current
  behavior or declare either earlier ADR accepted.


> Scope update (2026-09-29, owner decision): the current source CLI now assumes
> trusted execution and has no OS sandbox. This ADR's preparation/checking split
> remains proposed. Hostile-input containment is deferred until after this ADR and
> belongs to the caller or a future integration layer, not the verifier core.
> Resource limits and all logical proof/approval checks remain required. References
> below to the examined implementation describe the earlier architecture.

## 1. Observed pain

An agent can finish a migration and its Lean proof, but submitting the source to
`migration-check verify` starts another compilation process. Repeated submissions
require a Lean toolchain and a new temporary compilation
workspace. The caller cannot submit the already prepared mathematical evidence
through the public CLI.

The existing architecture is also difficult to explain in terms of three roles:
human, agent, and verifier. It is unclear which work the agent may perform freely,
which artifacts require human approval, and why checking a completed proof needs
to execute submitted programs. ADR 0002 proposes a substantial compilation cache
inside the verifier, increasing the amount of machinery involved in acceptance.

These are observations about the interface and implementation. We have not
measured how much latency a different boundary would save.

## 2. Goals

Give each role a clear responsibility: the human approves what correctness means;
the agent constructs a migration and evidence; the verifier decides whether that
evidence establishes the approved claim for the supplied SQL.

Make candidate proof preparation entirely agent-controlled. Agents should be able
to choose tactics, solvers, build strategies, and caches without the verifier
having to trust or repeat those activities. An incorrect or corrupted preparation
result must be rejected by checking its evidence.

Provide a verification path that consumes mathematical data and never executes
candidate Lean source, tactics, initializers, plugins, or build configuration.
Preserve the supported SQL semantics, proof obligations, axiom policy, statuses,
and all existing meaningful test scenarios, including installed-runtime checks.

Reduce work performed at acceptance time and measure both acceptance latency and
complete preparation-plus-verification cost. Moving work elsewhere is an
architectural improvement, but must not be reported as an end-to-end speedup
without measurements.

This ADR does not add SQL execution, live-database precondition checks, general
destructive-migration support, SNARKs, or a proof marketplace. It does not remove
human responsibility for specification fidelity or establish that the agent's
development environment is safe.

## 3. Investigation and root causes

### 3.1 One command currently prepares and checks proofs

The [CLI](../migration_check/cli.py) parses the actual SQL, generates Lean
inputs, calls [compile_project()](../migration_check/compile.py), and then
invokes a separate kernel checker. Compilation has four stages: starting-schema
data, approved requirements/current interpretation, migration data, and candidate
next interpretation/proofs. Source discovery and compilation happen again in each
private workspace.

Compilation performs elaboration: tactics and other Lean programs construct core
definitions and proof terms. Such programs can perform I/O. Consequently the
examined CLI used compilation sandboxes to contain that work; the current CLI
instead requires trusted execution. This is a consequence of accepting source for preparation, not
a mathematical requirement to reconstruct a proof before checking it.

[ProofChecker.lean](../ProofChecker.lean) already implements a separate logical
acceptance step. It imports declaration data without plugins or extension loading,
replays declarations, rejects protected-definition substitutions, reconstructs the
expected proposition, and checks the proof body and its dependencies. That split
is the foundation for this proposal; the gate is not a ready-made secure upload
endpoint.

### 3.2 Compiler artifacts are not a safe transport boundary

The current gate imports `.olean` files. Lean's official proof-validation guidance
warns that this loader assumes structurally valid files. Turning off initializers
does not validate arbitrary serialized memory structures. Regular-file checks,
checksums, and a sandbox do not prove that imported bytes express the intended
declarations or that a compromised checker returns a correct decision.

Lean's comparator workflow provides a relevant design: isolate preparation,
export proof data, validate the exported representation, and compare checked
declarations with a trusted challenge. This ADR follows that separation and
requires a version-compatible implementation investigation before integration.
This concern also applies to today's compiler-produced artifacts: untrusted
compile-time code can attempt to manufacture malicious output bytes.

The examined repository pins Lean 4.33.0. Official 4.34.0 release notes describe
additional soundness fixes relevant to crafted proofs. Implementation must review
and pin an appropriate patched checker/exporter combination; existing regression
success is not evidence that the current pin is adequate for hostile submissions.
No successful exploit against this repository was demonstrated in this review.

The current lean4export documentation describes an NDJSON declaration format, and
comparator provides parsing, replay, and statement-comparison components. Its
current master pins Lean 4.35.0-rc3, not this repository's 4.33.0. Reuse those
components behind a data-only entry point; invoking comparator's ordinary
build/export workflow would put source preparation back into acceptance. No
compatible revision set was built during this ADR's research.

### 3.3 Approval and SQL meaning cannot come from candidate claims

The optional [baseline check](../migration_check/baseline.py) binds approved
source bytes and their imported dependencies. It does not authenticate a human.
A correct source hash attached to an agent-produced compiled contract does not
establish that those compiled definitions came from that source.

Approved interpretations may import generated `SchemaInputs`. An elaborated
contract can therefore depend on the starting schema, even if its source files
are unchanged. Reusing it across arbitrary schemas would be incorrect.

The current trusted frontend also binds actual SQL to formal data. Delegating
compilation must preserve this binding: an agent cannot supply unrelated
`Generated.script` definitions and authorize them with its own manifest.

### 3.4 Smaller responsibility does not imply succinct verification

Checking a Lean proof still includes type checking and potentially expensive
reduction. Separating it from proof construction does not give SNARK-like cost
bounds. A future succinct-proof system could prove that a designated checker
accepted a particular contract/SQL request, but would add proving cost, integration
work, and cryptographic assumptions. Measure the ordinary checker first.

## 4. Assumptions and how to challenge them

| ID | Assumption connecting the design to its goals | Evidence that challenges it | Response |
| --- | --- | --- | --- |
| A1 | Current supported proofs and required definitions can be exported and checked without candidate execution | An existing positive/refutation case needs source execution during acceptance or loses essential declarations in export | Fix the export/checker integration; do not silently remove the case or enable native execution |
| A2 | An existing maintained export/checker implementation can provide the required data boundary | Version incompatibility, missing declarations, unsafe decoding, or inability to compare the full contract | Keep the feature experimental; the lead specifies a corrected protocol or revises this ADR before integration |
| A3 | Approved elaborated contracts can be registered without making approval impractical | Reviewers cannot relate the registered meaning to reviewed sources, or schema coupling forces unreasonable repeated approval | Improve review output or propose schema-parameterized contracts; do not auto-approve artifacts |
| A4 | Moving preparation out materially reduces acceptance work, and reusable preparation improves iteration | Export/decoding/replay dominates, or complete warm iteration costs exceed the old path | Keep the role separation if useful; optimize measured costs and withdraw unsupported speedup claims |
| A5 | The deployment can prevent agents from changing acceptance authority | Agent credentials can alter the registry, expected contract selection, checker, or authoritative result channel | Fix access controls or describe the deployment as local advisory checking, not an adversarial boundary |
| A6 | Runtime distribution can separate preparation dependencies from checking dependencies on both platforms | Checking still invokes a compiler/exporter or needs caller-controlled build configuration | Correct packaging or retain an explicit experimental limitation; never hide a preparation fallback |

Incorrect acceptance is a defect, not a performance tradeoff. Human intent,
faithful SQL modeling, sound proof checking, and protected operating infrastructure
remain assumptions of the product even if every experiment above succeeds.

## 5. Proposed architecture

### 5.1 Three roles, with preparation outside acceptance

| Role/component | Owns | Does not authorize |
| --- | --- | --- |
| Human and trusted registration process | Contract meaning, current interpretation, admitted states, dependencies, starting-schema/profile binding, approved contract identity | A migration merely because its author is trusted or its build succeeded |
| Agent and preparation tools | SQL, next/failure interpretations, proof search, candidate compilation, export, local and shared preparation caches | Changes to approved definitions, checker code, selected contract policy, or acceptance results |
| Verifier and trusted caller | Contract selection enforcement, actual SQL translation, proof-data decoding, target construction, checking, and authenticated delivery of the decision within the deployment | Business approval, live database applicability, or execution of the migration |

The submitted bundle contains proof data. Candidate sources may accompany it for
review and diagnostics, but do not establish acceptance. The agent may use an
incorrect compiler or poisoned cache: every submitted declaration and proof still
has to pass the verifier's checks.

The existing interpretation-fidelity limitation remains: arbitrary observation
functions can ignore storage. Keep the present next/failure-interpretation proof
obligations and documented additive guarantees. Do not use unconstrained
comparator definition holes for approved requirements, SQL, or semantics, or
claim that this separation makes arbitrary destructive migrations safe.

The minimum interface is conceptually:

```text
prepare(approved-contract, schema, migration, next-interpretation, proofs)
    -> proof-bundle

verify(expected-contract-id, schema, migration, profile, proof-bundle)
    -> status and exact input identities
```

The trusted caller chooses `expected-contract-id`. A bundle cannot select an
easier contract from a registry merely because that contract was approved for
some other use.

### 5.2 Register the approved meaning separately

A trusted administrative build prepares a review bundle containing the approved
source closure, source hashes, elaborated declaration data, and a readable account
of the logical state, predicates, current interpretation, and assumptions.
Preparation of that review bundle is still executable Lean work. Any required isolation belongs to the caller or
future integration layer. Merely producing the bundle is not approval.

Before publication, the trusted process validates the exported format and replays
the approved declarations against the pinned library and independently constructed
starting-schema definitions. The approved closure may depend on those roots, but
not on migration-dependent SQL definitions or candidate interpretations/proofs.
Human review does not replace these mechanical checks, and compiler success does
not establish them.

After explicit human review, an authorized operator publishes an immutable
contract record into a registry that agents cannot modify. The approved record
binds the declaration payload, source-closure provenance, exact starting-schema
SQL hash, SQLite profile, formal library, axiom policy, checker/export format
versions, and required named roots. V1 binds one concrete starting schema; making
contracts schema-parameterized is a separate extension.

The authoritative registered artifact is the reviewed elaborated meaning. Source
hashes provide traceability, not a proof of source-to-artifact equivalence. The
trusted registration pipeline and the human review of that relationship remain
part of the approval boundary. Changed sources, schema, profile, dependencies,
or semantic/checker identity require a new record and explicit authorization.

Use a versioned, domain-separated SHA-256 identity over a canonical manifest and
the exact payload digest. The trusted registry maps that identity to an authorized
record; hashing alone grants no authority. The operator controls which IDs remain
active. Verification resolves and snapshots one active record before checking;
revocation affects subsequent requests. Coordinating revocation with deployment
of an already accepted migration remains the caller's responsibility.

### 5.3 Let the agent prepare freely

The preparation SDK supplies the registered public definitions, matching toolchain
information, input generation, export, and diagnostics. The agent elaborates its
next interpretation and proof against those definitions and exports the required
mathematical declaration closure. The verifier never reads the agent's caches.

Candidate caching has no approval or determinism eligibility rule: stale or
incorrect cached results are simply untrusted evidence. Identity mismatches and
invalid proofs must fail at the same acceptance boundary as a newly fabricated
bundle. Cache optimizations can use normal Lake/incremental tooling first.

V1 exports the proof, next/failure interpretations, and their required dependencies,
including complete mutual/inductive declaration groups. Ordinary tactic
implementation code is not part of the submitted proof merely because it helped
construct it. Opaque theorem bodies needed for checking must be available.

### 5.4 Accept a bounded, validated data format

Adopt a pinned Lean proof-export representation supported by the comparator/
lean4export ecosystem, behind a repository-owned versioned envelope. Do not invent
a new logic or treat raw `.olean`, native libraries, or executable plugins as
submission data. Work package P1 must freeze the exact grammar and dependency
revisions before other packages implement against it.

Use one framed bundle file, not an extracted archive: format magic/version,
bounded manifest and payload lengths, then manifest and proof bytes. The manifest
contains claimed contract/request identities and payload digest for consistency;
the verifier computes those identities itself. No field selects executables,
external files, import paths, network locations, or checker configuration.

The decoder validates framing, lengths, encodings, record tags, reference bounds,
expression structure, declaration uniqueness, and supported declaration groups
before constructing kernel objects. Unknown executable records and unsupported
format versions fail closed. Reject ambiguous duplicate JSON keys, trailing data,
malformed references, and graph cycles where the format requires a DAG. Legitimate
mutual inductive groups must follow their explicit format rules.

All non-candidate references resolve to three protected sets: the pinned library,
verifier-generated SQL/schema/profile declarations, and the registered contract.
Construct the environment in that order, checking that the registered contract's
starting-schema references match the current protected schema before adding
candidate declarations. Approved definitions cannot depend on migration data.
Full exports that repeat protected declarations must match complete declaration
records, including bodies, universes, safety flags, constructors, and recursors;
names or types alone are insufficient. Candidate additions must be checked, with
the existing axiom/unsafe/partial policy enforced on every proof and target
dependency. No claimed axiom cache or missing opaque body substitutes for evidence.

V1 rejects extra candidate declarations outside the transitive proof,
interpretation, and target closure, except required members of mutual/inductive
groups. An unsafe tactic used only during preparation is not an unsafe proof
dependency: its implementation must be omitted from the bundle. The expected
target is constructed by the verifier; an unused candidate convenience alias has
no authority and is omitted as well.

### 5.5 Keep statement construction and acceptance trusted

For each request the verifier:

1. Snapshots the actual schema SQL, migration SQL, proof bytes, selected profile,
   and authorized contract record. Subsequent reads use those same bytes.
2. Checks contract authorization and identity, schema/profile compatibility, and
   bundle-format compatibility. Agent claims cannot supply missing authorization.
3. Parses actual SQL using the pinned frontend and applies existing admission and
   translation rules. It constructs structural kernel expressions for
   `startSchema`, `nextSchema`, `script`, and `profile` directly from validated
   model data. Candidate-supplied versions must match; no Lean source elaboration
   is needed for these literal inputs.
4. Decodes and checks proof data against the protected environment. Reconstructs
   the existing `VerificationConditions` target, including registered requirements,
   admitted states/current interpretation, and candidate next/failure interpretations.
5. Requires a closed positive proof, or a closed proof of the negated target for
   `VIOLATED`. Preserves the existing foundational axioms (`propext`,
   `Classical.choice`, `Quot.sound`), body checking, and protected-name checks.
6. Returns the status and computed request/contract/policy identities. Only a
   checked positive proof yields CLI exit zero. A refutation is not a native SQL
   counterexample; failure to prove is not a refutation.

Define the request identity from a versioned canonical record containing the
contract ID, exact schema/migration byte hashes, selected profile, and checking
policy identity. Require the bundle's claimed request fields to equal those
computed fields. Include the checked payload digest in the result. Candidate
source hashes, when reported, are provenance supplied by the author, not a checked
source-to-proof correspondence.

Direct expression construction replaces the current generated-source compilation
boundary. It is trusted code and needs independent tests against today's emitter.
It must preserve inferred result schemas and all supported literals/SQL operations.

The checker still needs budgets for decoding, proof size, memory, and time.
OS isolation is deferred to a caller or integration layer after this ADR.
Moving tactics elsewhere removes their
intentional execution from acceptance, but does not eliminate implementation bugs
or denial-of-service risk. A checker crash, timeout, malformed output, or incomplete
result never counts as acceptance.

The verifier installation, registry, runtime library, and authoritative result
channel must be inaccessible for agent modification. Separate commands under the
same unrestricted account do not enforce that rule. A service or CI deployment
must show the actual permission boundary; an agent's console message is not the
verifier's decision.

### 5.6 Compatibility, caching, and alternatives

Retain the existing source-based `verify` command while introducing explicit
`prepare` and `verify-bundle` commands. Source verification remains a convenience
workflow that executes source preparation under the trusted-execution assumption. Preserve its existing optional
baseline behavior and label it as verification against supplied requirements when
no registered approval is used. Do not silently register those requirements.

The new `verify-bundle` path requires an authorized registered contract and never
falls back to source compilation after a missing, invalid, or incompatible bundle.
Both paths should eventually use the validated proof-data checker; the legacy
wrapper can construct an ephemeral supplied-contract context without claiming
human approval. Future containment tests belong to the integration that supplies isolation.

If this ADR is accepted, do not implement ADR 0002's qualified stage cache inside
the acceptance process. Retain stage timings and move ordinary compilation reuse
to preparation. Reuse of a registered contract is reuse of an approved artifact,
not acceptance of an agent-owned compilation-cache entry.

ADR 0001's case discovery and build caching remain useful. Preserve all existing
test purposes and installed coverage. Cached test results are allowed where their
complete relevant inputs and trustworthy provenance are captured. Host-dependent
isolation/installer tests need separately justified cache policy; there is no
blanket requirement for every proof test to execute on every unchanged CI run.
Document any change to current CI policy explicitly in its implementation PR.

Keeping source compilation in the verifier is a valid compatibility option, but
retains its repeated work and execution boundary. Accepting raw compiler artifacts
does not meet this proposal's threat model. SNARK/zkVM integration is deferred:
first measure the data-only checker; any later receipt must bind the designated
checker and complete request, not merely assert that some program returned success.

## 6. Implementation and migration

### 6.1 Freeze the protocol before parallel implementation

The formal methods lead owns P1 and a different qualified reviewer challenges it.
Junior developers can implement the resulting fixtures, framing, CLI, registry
plumbing, and packaging; they must not infer missing logical acceptance rules.

P1 produces `docs/proof-format-v1.md` with exact exporter/checker revisions,
licenses, grammar, framing/canonicalization, declaration comparison rules,
permitted axioms, named roots, and golden accepted/rejected bundles. Demonstrate
ordinary, allowed-failure, and Atuin proofs on both supported platforms. Compare
the validated import with the current gate and exercise an independent checker
such as nanoda during qualification; it is not automatically a new runtime
requirement. Review upstream soundness fixes before selecting the pinned version.

Set explicit byte/node/depth/memory/time limits there, with fixture measurements
and headroom recorded. Retain the current 1 MiB SQL limit and 30-second production
gate deadline unless a separate measured change is reviewed. New proof-format
limits must accommodate existing supported cases; do not invent silent exclusions.
Gate timeout, malformed evidence, or unsupported proof-format version yields
`UNVERIFIED`; missing inputs/unauthorized or incompatible contract selection yields
`INPUT_ERROR`; existing SQL `UNSUPPORTED` behavior remains unchanged. Only checked
negation yields `VIOLATED`.

If safe decoding or complete statement comparison cannot be demonstrated, P1
reports the concrete obstacle and stops bundle integration. Continue independent
pytest/timing work; do not ship a raw `.olean` fallback.

### 6.2 Work packages

All new paths below are proposed implementation paths, not files already present.

| Package | Owner and files | Depends on | Completion evidence |
| --- | --- | --- | --- |
| P0: baseline | Integration engineer; timing hooks in `cli.py`, `compile.py`, `source_closure.py`; case inventory | None | Current discovery/compile/gate times and all source/installed scenarios listed; no changed acceptance |
| P1: protocol spike | Formal lead; `docs/proof-format-v1.md`, isolated export/checker prototype, pinned dependencies | P0 | Safe data round trip, protected-definition attacks, exact input binding, toolchain compatibility, budgets, and reviewer sign-off |
| P2: registration | Integration engineer with formal reviewer; new `contract_registry.py`, administrative CLI, review output | P1 | Reproducible review procedure, immutable authorized records, schema binding, permission and revocation tests; no automatic approval |
| P3: preparation | Integration engineer; new `prepare.py`, exporter adapter, refactor `compile.py` | P1 | Agent produces valid bundles using cold/warm builds; no access to authority required; useful preparation diagnostics |
| P4: checker | Formal lead with independent reviewer; validated importer, direct SQL-expression adapter, refactor `ProofChecker.lean` | P1, P2 | Positive/refutation parity and adversarial rejection without compiler or candidate source access |
| P5: interface/runtime | Integration engineer; `cli.py`, `runtime.py`, `packaging/`, tests and docs | P2, P3, P4 | `prepare`/`verify-bundle`, legacy adapter, installed prepare+check and checking-only distributions on Linux and macOS |
| P6: migration/evidence | Technical lead; CI selection, docs, ADR status and benchmark report | P5 | Full case mapping, reviewed limits/authority boundary, measured results, owner review of product implications |

After P1, P2/P3 and independent fixtures can proceed concurrently. Preserve the
small `path:./nix` development-environment boundary. Pin new tool dependencies using
the established Nix/Lake packaging arrangement; do not copy the checkout into that
environment or require network downloads during acceptance.

### 6.3 Required acceptance cases

Use descriptive, independently selectable cases following ADR 0001 where
available. Keep a mapping from every current scenario to its successor; splitting
the interface is not a reason to delete installed-package or adversarial coverage.

| Family | Required evidence |
| --- | --- |
| Existing behavior | Honest proofs, allowed failures, refutations, CLI rejections, and installed scenarios retain their intended outcomes; approved registered fixtures cover the bundle path |
| No source execution | Bundle verification succeeds with compiler/exporter executables unavailable; submitted source, initializers, plugin paths, and Lake configuration cannot run |
| Contract authority | Unknown, inactive, or wrong expected ID fails; a self-consistent agent manifest cannot register a weaker contract or replace protected definitions |
| Schema/profile/SQL binding | Change each actual input independently; an unchanged bundle cannot prove the wrong generated data, even with forged matching manifest labels |
| Registration fidelity | Same source hash plus different compiled declarations cannot replace an authorized record; schema-dependent interpretation cannot reuse another schema's registration |
| Literal construction | Compare structural definitions with today's emitter for every supported model constructor, strings/Unicode, numbers, and result-schema calculation; protected-name substitutions fail |
| Proof policy | Forged body, `sorry`, extra premise, forbidden axiom, unsafe/partial relevant dependency, missing opaque body, proof only of a weaker expected alias, and incomplete dependency closure fail |
| Declaration closure | An honest proof constructed with unsafe tactic implementation code still passes after that code is omitted; irrelevant candidate records reject, required mutual/inductive group members remain allowed, and legitimate generated-input references resolve |
| Malformed evidence | Truncation, oversized lengths, duplicate keys/names, invalid references, invalid expression cycles, unknown tags, bad encodings, and native/plugin records fail within budgets |
| Snapshot/permissions | Concurrent changes cannot swap checked bytes; agent cannot change registry/checker/library or forge the trusted result channel; no archive/path-following escape |
| Untrusted caches | Arbitrary stale/corrupted agent cache outputs never bypass input matching or checking; honest warm output has the same semantics as cold output |
| Failure classification | Preparation failure, decode error, checker crash/timeout, and unknown format never produce `VERIFIED` or `VIOLATED` |
| Compatibility | Legacy optional-baseline semantics and artifacts remain documented; bundle checking never executes a hidden source fallback; both native distributions install correctly |

Current gate parity is useful regression evidence, not a complete correctness
oracle: malformed-artifact and upstream kernel fixes may reveal old defects. Add
independent expected outcomes for those cases and record intentional corrections.

### 6.4 Performance experiment, rollout, and rollback

Measure at least three trials per mode on each supported native platform: current
source verification; first registration plus cold preparation/checking; warm agent
preparation plus checking; and checking an already prepared bundle. Include the
Atuin example, a small positive proof, a refutation, and rejected evidence. Report
registration separately with its expected reuse count. Record source/export sizes,
compiler invocations, CPU/wall time, peak memory, decode time, and kernel time.

Acceptance-path compiler invocation count must be zero. Report complete iteration
cost as well as acceptance latency, with host/runtime identities and unchanged
resource limits. If speed does not improve, report which assumption failed rather
than raising deadlines or removing cases. A later succinct-proof proposal requires
measured checker cost and a matching prover-cost experiment.

Release the new interface as opt-in after P1-P5. Run differential source/bundle
checks in CI during migration; retain the source workflow until installed parity,
adversarial review, and approval usability are demonstrated. Update the engineering
brief, trust-boundary documentation, source-staging guide, installation guide, and
CI policy together when behavior changes. Registration and any dependency upgrade
receive their own review; an existing baseline is not automatically converted
into a new approval.

Rollback disables bundle acceptance and preserves the reviewed legacy source path
for its documented use. Do not silently redirect hostile bundles into legacy
artifact import, and do not treat rollback as evidence that old checker security
issues are resolved. Versioned bundles and contract records remain inspectable;
unsupported versions reject, never reinterpret. No rollback rewrites approved
requirements, refreshes baselines, or deletes user caches.

## Research references

Consulted 2026-09-28. Repository observations refer to the revision above; external
documentation describes available designs, not tested compatibility with that pin.

- [Current source staging](source-staging.md), [kernel gate](kernel-gate.md),
  [approval boundary](approved-baseline.md), and [remaining trust](trust-boundary.md).
- [Lean: validating proofs, hostile module files, and comparator](https://lean-lang.org/doc/reference/latest/ValidatingProofs/).
- [Lean: elaboration and kernel checking](https://lean-lang.org/doc/reference/latest/Elaboration-and-Compilation/).
- [Comparator implementation](https://github.com/leanprover/comparator).
- [Lean declaration exporter](https://github.com/leanprover/lean4export),
  [export format](https://github.com/leanprover/lean4export/blob/master/format_ndjson.md),
  and [comparator toolchain pin](https://github.com/leanprover/comparator/blob/master/lean-toolchain).
- [Lean 4.34.0 soundness fixes](https://lean-lang.org/doc/reference/latest/releases/v4.34.0/).
- [RISC Zero receipt semantics](https://docs.rs/risc0-zkvm/latest/risc0_zkvm/struct.Receipt.html):
  illustrates binding outsourced execution to a designated program and public
  outputs; no integration or performance claim is made here.
