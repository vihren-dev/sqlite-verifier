# ADR 0003: Separate agent proof preparation from verification

- Status: Proposed
- Date: 2026-09-28; refactored 2026-09-29 around measured latency
- Implementation examined: `19e015a11406f6dc26351e673cf355d072273034`
- Decision owners: product owner for guarantees and workflow; formal methods lead
  for proof acceptance
- Related: [ADR 0001](adr-0001-pytest-and-nix-ci.md) (accepted, partly superseded),
  [ADR 0002](adr-0002-compile-project-cache.md) (proposed; replaced by this ADR if
  accepted), [ADR 0004](adr-0004-model-conformance-validation.md) (depends on this
  ADR), [latency experiments](../experiments/adr-0003-latency/README.md),
  [deferred trust design](adr-0003-trust-extension.md)

## Decision requested

Adopt one architecture for two goals, in this order:

1. **Now, latency.** The agent prepares proofs with its own tools and exports the
   resulting declarations with lean4export. A new `verify-bundle` path checks that
   exported data against the verifier's trusted library, generated SQL inputs and
   approved contract. It never compiles candidate source. The verifier still
   assumes trusted execution.
2. **Later, trust.** The same data path is the basis for accepting proofs from
   untrusted agents. The added requirements (contract registry, hardened decoding,
   independent kernel, deployment authority) are
   [deferred](adr-0003-trust-extension.md) and not part of this decision.

Approve the latency milestone's prototype work package (P1 below). Implementation
beyond P1 depends on P1 meeting its exit criteria.

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

Checking exported declarations removes every compile process from acceptance and
checks each declaration once. The experiments exported the examples with
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

Projected acceptance latency is 0.5–1.5 s for the small examples and 2.6–3.6 s for
Atuin, against 6.2 s and 19.5 s today. The range covers building the generated SQL
declarations, which the prototype did not measure: up to about 1.0 s if they are
still compiled by Lean, less if the checker constructs them directly. Target
reconstruction and the axiom audit are not in the prototype either; today's gate
performs them and they are expected to take milliseconds. An agent that changes
only its proof pays an incremental compile of the changed modules (0.5 s or more
each) plus a 0.6–0.7 s export before submitting.

## Decision

### Roles

| Role | Owns | Does not decide |
| --- | --- | --- |
| Human | The approved contract: requirements, current interpretation, admitted states, dependencies, starting schema and profile | Whether a particular migration is proved |
| Agent | Migration SQL, next and failure interpretations, proofs, how they are built and cached, and the exported bundle | Approved definitions, checker code, or the result |
| Verifier | Translating the actual SQL, building the expected target, checking the bundle, and the status | Business approval or applying the migration |

### Latency milestone (trusted execution)

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
- **Approved contract reuse.** The verifier compiles the approved sources and
  generated schema inputs itself and may keep the result in a verifier-owned
  store keyed by the approved source hashes, schema SQL hash, profile and library
  version. This is ADR 0002's approved-stage reuse, placed outside candidate
  preparation. Approval semantics are unchanged: the existing optional baseline
  still pins source bytes, and nothing is registered or approved automatically.
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
| A4 | Acceptance becomes several times faster without slowing agent iteration | Measured check and export costs above; generated inputs, target checks and incremental builds not yet measured | Report measured end-to-end cost; fall back to the alternatives below |
| A5 | Direct construction of generated inputs matches today's emitter | Not yet tested | Keep compiling generated inputs with Lean |

## Alternatives

| Option | Expected effect on the small / Atuin examples | Why not chosen as the target |
| --- | --- | --- |
| Keep the current path | 6.2 s / 19.5 s | Leaves most time in process start-up and repeated compilation |
| Tune the current path: gate imports only needed trusted modules; reuse approved-stage compilation (ADR 0002) | Estimated about 2.3 s / 4.9 s saved (sum of measured stage times, not measured end to end) | Still compiles candidate source in acceptance; no route to trust |
| Comparator's full replay | 5.5 s / 7.3 s check | Little gain for small proofs; string-literal replay issue (comparator #93) |
| Data path with trusted library (this ADR) | Projected 0.5–1.5 s / 2.6–3.6 s | Chosen |

If P1 fails its exit criteria, apply the tuning option instead: it needs no new
dependency and keeps the current trust model.

## Plan

| Package | Scope | Exit criteria |
| --- | --- | --- |
| P0: baseline | Done: [latency experiments](../experiments/adr-0003-latency/README.md) | Stage and data-path costs recorded |
| P1: prototype | Checker executable with target reconstruction and axiom policy; library-omitted export proposed upstream or pinned as a local patch; bundle format v1 written down in `docs/proof-format-v1.md`; Linux measurement | All existing positive, refutation, allowed-failure and Atuin cases give today's statuses through the data path on both platforms; protected-declaration substitution, `sorry`, forbidden axioms and a wrong target fail; measured acceptance latency meets the projection |
| P2: interface | `prepare`, `verify-bundle`, approved-contract reuse, packaging for both platforms | Installed runtime runs both commands; source `verify` unchanged |
| P3: generated inputs | Versioned structural encoding and direct construction, shared with ADR 0004 | Matches today's emitter for every supported constructor, literal and result schema |
| P4: documentation and CI | Trust-boundary, source-staging, install and CI docs; case mapping | Each property tested at one layer, as in the current test policy |

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
