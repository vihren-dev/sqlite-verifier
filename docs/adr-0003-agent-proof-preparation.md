# ADR 0003: Separate agent proof preparation from verification

- Status: Accepted 2026-09-29: the data path, by owner decision after P1 (see
  below). P2 is next.
- Date: 2026-09-28; refactored 2026-09-29 around measured latency, then revised
  after review (contract reuse, end-to-end criteria, comparative experiment);
  amended 2026-09-29 with the owner decision
- Implementation examined: `19e015a11406f6dc26351e673cf355d072273034`
- Decision owners: product owner for guarantees and workflow; formal methods lead
  for proof acceptance
- Related: [ADR 0001](adr-0001-pytest-and-nix-ci.md) (accepted, partly superseded),
  [ADR 0002](adr-0002-compile-project-cache.md) (proposed; replaced by this ADR if
  accepted), ADR 0004, model conformance validation (draft, not yet published; depends on this
  ADR), [latency experiments](../experiments/adr-0003-latency/README.md),
  [deferred trust design](adr-0003-trust-extension.md)

## Owner decision (2026-09-29)

**Continue with the data path.** P1 ran on macOS and Linux with correct statuses in
all 468 runs ([results](../experiments/adr-0003-latency/p1-results.md)). Applied
literally, the pre-registered decision rule below gives **ship tuning**: the data
path was slower than tuning in some required comparisons (refutation SQL edits on
both platforms by 25–46%, and the small proof edit on macOS by 3%). The owner
overrides that outcome for these reasons:

- The rule weighted every example equally. The small and refutation examples are
  synthetic fixtures that take a few seconds with either option; Atuin is the only
  realistic case, and real agent proofs are expected to resemble it.
- Proof retries dominate agent iteration. For Atuin proof edits the data path's
  edit-to-result time is 45–59% below tuning's on both platforms (macOS 9.3 s
  against 18.1 s with a fresh contract; Linux 7.7 s against 13.9 s).
- Acceptance alone is faster than tuning in every measured cell: 0.95–2.6 s against
  2.3–4.6 s for the small examples, and 3.2–7.7 s against 11.2–18.1 s for Atuin.
- The data path is the basis for the deferred trust milestone.

Known weaknesses carried into P2: SQL edits (Atuin only 2–5% better than tuning;
refutation 25–46% worse), approved-contract edits (slower than tuning: by 1.3–1.7 s for
the small examples, 0.5–1.1 s for Atuin), and the added maintenance cost listed in
Alternatives. Tuning's gate narrowing and stage reuse are kept; the data path uses
both.

## Decision requested before P1

Approve a bounded comparative experiment (P1 below) between two ways of reducing
verification latency:

- **Data path** (proposed target): the agent prepares proofs with its own tools
  and exports the resulting declarations with lean4export; a new `verify-bundle`
  path checks that data against the verifier's trusted library, generated SQL
  inputs and approved contract, without compiling candidate source.
- **Tuning** (baseline alternative): keep `verify` compiling everything, but
  narrow the gate's imports and reuse eligible verifier-compiled stages.

Adopt the data path only if P1 meets the decision rule below on each supported
platform. Otherwise ship tuning. Both options assume trusted execution.

The data path is also the basis for later accepting proofs from untrusted agents.
That is a separate benefit with its own cost (see Alternatives), not a latency
argument. The added trust requirements (contract registry, hardened decoding,
independent kernel, deployment authority) are
[deferred](adr-0003-trust-extension.md) and not part of this decision.

## Current state (2026-09-29)

- `migration-check verify` compiles the SQL-derived inputs, the approved contract
  and the candidate sources in separate Lean processes, then runs an independent
  kernel gate over the resulting `.olean` files
  ([source staging](source-staging.md), [kernel gate](kernel-gate.md)).
- The verifier assumes trusted execution and has no OS sandbox
  ([trust boundary](trust-boundary.md)). Logical checks, approval baselines and
  resource limits remain required.
- A warm verification takes 6.2 s for a small proof and 19.5 s for the Atuin
  example on an Apple Silicon Mac. Most of that is not proof checking (below).

## Where the time goes

Measured with the [latency experiments](../experiments/adr-0003-latency/README.md)
(one machine, medians of three warm runs; Linux not measured).

| Example | Total | Lean compile processes | Compile | Kernel gate |
| --- | --- | --- | --- | --- |
| small positive | 6.2 s | 7 | 3.7 s | 2.2 s |
| refutation | 6.2 s | 7 | 3.6 s | 2.2–2.4 s |
| Atuin | 19.5 s | 14 | 11.5–12.2 s | 6.4–7.2 s |

- Every compile process pays about 0.5 s to start Lean and import
  `SqliteVerifier`, whatever the module contains. Small cases spend almost all of
  their compile time on this floor.
- The gate imports `Lean` and `SqliteVerifier` (about 1.3 s) before replaying
  anything.
- Kernel work is duplicated: compilation checks every declaration, and the gate
  replays approved and candidate declarations again.
- The approved contract and generated inputs are recompiled on every request,
  although they rarely change between an agent's attempts.

## Why a data path helps latency

Checking exported declarations removes candidate compilation from acceptance and
checks each candidate declaration once. The experiments exported the examples with
lean4export `v4.33.0`, which builds and runs on the pinned Lean 4.33.0 unchanged,
and timed three checking strategies:

| Example | Full replay from empty environment | Trusted library + full export | Trusted library + library-omitted export |
| --- | --- | --- | --- |
| small | 5.5 s | 1.5 s | 0.44 s |
| refutation | 5.0 s | 1.5 s | 0.44 s |
| Atuin | 7.3 s | 3.8 s | 2.6 s |

- Comparator's own kernel step re-checks the whole closure, including Lean's
  standard library. That saves little for small proofs, so the checker must not
  work that way in this milestone.
- Importing the verifier-owned `SqliteVerifier` library and replaying only the
  declarations it lacks costs 1.5 s. Parsing the 25–29 MB export takes 0.9 s of
  that, because it repeats about 5,000 library declarations.
- Omitting library declarations from the export (a small exporter change, tested
  as a patch) shrinks it to 11–15 KB for small proofs and 1.5 MB for Atuin. Export
  then takes 0.6–0.7 s and checking 0.44 s. Atuin's remaining 2.6 s is almost all
  kernel checking of its 33 candidate declarations (2.1 s), which no architecture
  avoids.
- Replaying the approved contract and generated inputs costs 1–65 ms, so
  reusing a prepared contract matters for compile time, not for check time.

Acceptance is only part of the workflow. Much of the saving comes from moving
candidate compilation into the agent's `prepare` step, not from removing it. The
estimates below add up measured stage times from the experiments. They are not
end-to-end measurements, and P1 must replace them.

| Estimate (small / Atuin) | Today | Tuning | Data path |
| --- | --- | --- | --- |
| Acceptance, approved contract compiled fresh | 6.2 s / 19.5 s | 5.4 s / 18.7 s | 2.0–2.6 s / 7.0–7.5 s |
| Acceptance, approved contract reused | — | 3.9 s / 14.6 s | 0.4–1.0 s / 2.6–3.1 s |
| Agent edit to result, proof-only change, contract reused | 6.2 s / 19.5 s | 3.9 s / 14.6 s | 1.5–2.1 s / 3.8–4.3 s |

- Tuning saves about 0.8 s by importing only the trusted modules a request needs
  (1.3 s versus 0.5 s for the library alone) and, when reuse is eligible, the
  approved and schema compiles (about 1.5 s small, 4.1 s Atuin).
- Data-path acceptance adds the generated SQL inputs (up to 0.5 s if still compiled
  by Lean) to the 0.44 s / 2.6 s check. A freshly compiled contract adds the schema
  and approved compiles plus their dependency discovery (about 1.6 s / 4.4 s).
- An agent's edit-to-result time on the data path adds an incremental compile of
  the changed modules (0.5 s or more each; 2.4 s for Atuin's largest) and a
  0.6–0.7 s export. A migration SQL change recompiles every candidate module that
  imports the generated SQL inputs, so it costs more than a proof-only change.
- Target reconstruction and the axiom audit are not in the prototype checker;
  today's gate performs them and they are expected to take milliseconds.
- Under ADR 0002's eligibility rules, approved closures start ineligible for
  reuse. The fresh-contract row is therefore the realistic starting point.

## Decision

### Roles

| Role | Owns | Does not decide |
| --- | --- | --- |
| Human | The approved contract: requirements, current interpretation, admitted states, dependencies, starting schema and profile | Whether a particular migration is proved |
| Agent | Migration SQL, next and failure interpretations, proofs, how they are built and cached, and the exported bundle | Approved definitions, checker code, or the result |
| Verifier | Translating the actual SQL, building the expected target, checking the bundle, and the status | Business approval or applying the migration |

### Data path (adopted; trusted execution)

This section specifies the data path. P1 prototyped it; P2 turns it into the
supported interface.

- **`prepare`** (agent side, a convenience the agent may replace): builds the
  candidate modules against the approved contract with ordinary incremental Lake
  builds, then exports the proof closure with lean4export, omitting declarations
  from the pinned library. The verifier never reads agent caches; a stale or
  wrong cache produces a bundle that fails checking.
- **`verify-bundle`** (acceptance): parses the actual schema and migration SQL
  with the existing frontend and admission rules, then:
  1. obtains the approved contract and generated inputs as trusted Lean
     declarations;
  2. imports the pinned library from verifier-owned `.olean` files;
  3. parses the bundle;
  4. requires any declaration that repeats a trusted one to match it as a complete
     record after lean4export's normalization (metadata removed, `let` nondep flags
     false);
  5. replays the remaining candidate declarations;
  6. reconstructs `VerificationConditions`, checks the closed positive or negated
     proof, and applies today's axiom and unsafe/partial policy.

  Statuses and exit codes are unchanged. Malformed, incompatible or incomplete
  bundles are `UNVERIFIED`. A missing contract is `INPUT_ERROR`.
- **Approved contract.** The verifier compiles the approved sources and generated
  schema inputs itself, as today. It may reuse a previous compilation only under
  the rules below.
- **Generated SQL inputs.** First keep compiling them with the pinned Lean (a
  trusted input, about 0.5 s each). Replacing that compile with direct
  construction from a versioned structural encoding of frontend results is a
  follow-up. ADR 0004 plans to reuse the same encoding for model-conformance
  cases.
- **The checker** is a repository-owned Lean executable built from lean4export's
  parser and the relevant comparator code (comparison and axiom traversal) at
  their `v4.33.0` tags. It does not use comparator's command line, which builds
  source and needs the Linux-only `landrun` sandbox, and it does not replay from
  an empty environment.
- **The source `verify` command stays** as the compatibility and human workflow.
  It may later run `prepare` and `verify-bundle` internally. Neither path falls
  back to the other silently.

### Approved contract reuse

Reuse needs two things (ADR 0002 §3.3):

- **Determinism:** compiling the approved closure must depend only on the
  identified inputs.
- **Provenance:** a reused artifact must come from the verifier's own compilation
  of those inputs.

A verifier-owned store provides provenance only. Source hashes do not fix meaning
if elaboration reads undeclared files, time, randomness or other external state.

Adopt ADR 0002's eligibility policy (§5.2, §6.1):

- Generated schema and SQL inputs become eligible after their templates and
  runtime are qualified.
- An approved closure becomes eligible only when a verifier-owned registry records
  a separate review of that exact closure and runtime. Business approval and a
  matching user baseline do not grant eligibility.
- Everything else compiles fresh. Reuse is an optimization with a fresh-compilation
  fallback, never a condition for a result.
- The reuse key includes the approved source/module map, schema SQL hash, profile,
  Lean toolchain, library and checker identity, and the exporter normalization
  version.

With this policy approval semantics are unchanged: an eligible reuse yields the
same declarations a fresh compile would. The alternative is to redefine approval
as binding a prepared, reviewed artifact rather than source bytes. That changes
approval semantics and needs an owner decision; it belongs to the registry in the
[trust extension](adr-0003-trust-extension.md), not to this decision.

### Deferred: trust milestone

Once agents or their outputs are treated as hostile, the same path gains a
registered contract authority, bounded and validated decoding of a framed bundle,
an independent kernel (Nanoda), and deployment permission boundaries. These are
described in the [trust extension](adr-0003-trust-extension.md). ADR 0004's
independent-replay tier depends on the independent kernel. Nothing in the
latency milestone may accept candidate `.olean` files, because that would block
this step.

## Assumptions

| ID | Assumption | Evidence so far | If it fails |
| --- | --- | --- | --- |
| A1 | Supported proofs export completely and replay without candidate execution | Small, refutation and Atuin exported and replayed on 4.33.0 | Fix the exporter or checker; do not drop the case |
| A2 | Library-omitted exports are sound when every omitted name resolves to the trusted library | Patch prototype; replay succeeded for all three examples | Keep full exports and accept the 0.9 s parse cost |
| A3 | Normalized complete-record comparison is the right protection for repeated declarations | 0 mismatches over about 5,100 repeated declarations per example after normalization | Specify the exact comparison in P1 before implementation |
| A4 | Both acceptance and agent edit-to-result time improve enough over tuning to meet the decision rule | P1: acceptance faster everywhere; edit-to-result 45–59% faster for Atuin proof edits, but slower or marginal for SQL edits ([results](../experiments/adr-0003-latency/p1-results.md)) | Not met as written; owner decision above. P2 re-measures SQL edits after dependency-aware preparation |
| A6 | Useful approved closures (starting with Atuin) can be qualified as deterministic for reuse | Not reviewed | Compare options with fresh contracts; reuse benefits both options equally |
| A5 | Direct construction of generated inputs matches today's emitter | Not yet tested | Keep compiling generated inputs with Lean |

## Alternatives

Latency comparison uses the estimates above until P1 measures them. Future trust
is listed separately and does not count as a latency benefit.

| Option | Latency (estimated, small / Atuin) | Added cost | Future trust |
| --- | --- | --- | --- |
| Keep the current path | 6.2 s / 19.5 s | None | Would need a new design |
| Tuning (narrow gate imports, eligible stage reuse) | Acceptance 3.9–5.4 s / 14.6–18.7 s | Small changes to the gate and compile staging; the eligibility registry | Would need a new design |
| Comparator's full replay | Check alone 5.5 s / 7.3 s | As data path | Yes, but fails on string literals (comparator #93) |
| Data path with trusted library | Acceptance 0.4–2.6 s / 2.6–7.5 s | Two pinned upstream components and a local exporter patch until upstreamed; a bundle format; `prepare` and `verify-bundle` to package, test and document | Basis for the [trust extension](adr-0003-trust-extension.md) |

Eligible reuse benefits both tuning and the data path; it is not an advantage of
either. Whether future trust compatibility justifies the data path's added cost
when latency gains are small is an owner decision under the rule below.

## Plan

| Package | Scope | Exit criteria |
| --- | --- | --- |
| P0: baseline | Done: [latency experiments](../experiments/adr-0003-latency/README.md) | Stage and data-path costs recorded |
| P1: comparative experiment (done 2026-09-29; [results](../experiments/adr-0003-latency/p1-results.md)) | Prototypes of both options. Tuning: narrowed gate imports and eligible generated-stage reuse. Data path: checker with target reconstruction and axiom policy, library-omitted export (upstream or pinned patch), and a scripted `prepare` using incremental Lake builds. Measure both on macOS and Linux | Correctness: all existing positive, refutation, allowed-failure and Atuin cases give today's statuses through both prototypes; protected-declaration substitution, `sorry`, forbidden axioms and a wrong target fail. Measurements: see below |
| P2: data path interface | Make `prepare` and `verify-bundle` supported commands (no longer experimental), installed and tested on both platforms. Make `prepare`'s incremental build follow each module's actual imports, so an edit recompiles only the modules that depend on it (the P1 prototype recompiled every module after the first changed one). Keep tuning's narrowed gate imports and opt-in stage reuse, and the eligibility registry. Decide whether to upstream the library-omitting export option to lean4export or keep the pinned patch. Re-run the P1 matrix | Installed runtime runs both commands on macOS and Linux; `verify` results unchanged; bundle correctness cases pass in the installed runtime. SQL-edit cells re-measured on both platforms and reported against tuning, with any remaining gap explained. Data path no slower than today's `verify` in any cell, beyond measurement noise |
| P3: generated inputs | Versioned structural encoding and direct construction, shared with ADR 0004 | Matches today's emitter for every supported constructor, literal and result schema |
| P4: documentation and CI | Trust-boundary, source-staging, install and CI docs; case mapping | Each property tested at one layer, as in the current test policy |

P3 applies because the data path was adopted. P4 documents and tests the data
path together with the kept tuning changes.

### P1 measurements and decision rule

Measure on each supported platform, on one machine per platform, with at least
five warm trials and one cold trial per cell, for today's `verify`, tuning and the
data path:

- **Examples:** small positive, refutation and Atuin.
- **Changes:** proof-only edit, migration SQL edit, and approved-contract edit
  (always a fresh contract).
- **Contract state:** approved contract compiled fresh, and reused where eligible.
- **Two times per cell:** acceptance (`verify`, or `verify-bundle` alone) and edit
  to result (from the agent's saved change to a status, including `prepare` and
  export).

Record host, toolchain and repository revision. Report medians and ranges, not one
number.

Decision rule, applied to medians. The *required comparisons* are the data path's
edit-to-result time against tuning's, for proof-only and SQL changes, for every
example, on both macOS and Linux. A *regression* is any measured cell, on either
platform, where the option is slower than today's `verify`. Exactly one outcome
applies, checked in this order:

1. **Adopt the data path** if both prototypes pass P1's correctness criteria, every
   required comparison is at least 30% faster, and the data path has no
   regression.
2. **Owner decision** if both prototypes pass P1's correctness criteria, every
   required comparison is faster but at least one misses 30%, and the data path
   has no regression. The owner chooses between the two options, weighing future
   trust compatibility against the added cost listed in Alternatives.
3. **Ship tuning** in every other case, including mixed-platform results. Tuning
   ships only if it passes P1's correctness criteria and has no regression. If it
   fails either check, keep the current path and record why.

Keep the 1 MiB SQL limit and the 30-second gate deadline unless a measured change
is reviewed. Rollback disables `verify-bundle`; the source path is unaffected.

## References

- [Latency experiments](../experiments/adr-0003-latency/README.md) and the
  [deferred trust design](adr-0003-trust-extension.md)
- [Component research](0003-component-research.md) (proposal input; where it
  conflicts with this ADR, this ADR decides)
- [Lean: validating proofs and comparator](https://lean-lang.org/doc/reference/latest/ValidatingProofs/)
- [lean4export](https://github.com/leanprover/lean4export) and its
  [NDJSON format](https://github.com/leanprover/lean4export/blob/master/format_ndjson.md);
  [comparator](https://github.com/leanprover/comparator); both tagged `v4.33.0`
- [Comparator issue #93](https://github.com/leanprover/comparator/issues/93)
