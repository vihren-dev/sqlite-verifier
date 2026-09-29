# ADR 0003 component research and concrete implementation proposal

Date: 2026-09-28. Status: proposed implementation of
[ADR 0003](adr-0003-agent-proof-preparation.md), based on source inspection.
No toolchain build, exported SQLite proof, or performance benchmark was run in
this research environment. The component choices below are concrete; their
qualification remains an implementation gate, not an established result.

## Recommended stack

Use Lean/Lake and lean4export for agent-controlled preparation. Build a small
repository-owned Lean executable using comparator's comparison/axiom libraries
and a hardened export reader. Require both the official Lean kernel and Nanoda
to accept submitted proof data. Keep Python for the existing SQL frontend,
registry/request handling, process isolation, and result protocol.

Do not invoke standalone comparator's default CLI from the acceptance path: it
builds and exports source. Do not introduce a new proof calculus, bespoke binary
proof format, or SNARK layer. Use ordinary NDJSON 3.1.0 exports with explicit
request arguments and immutable snapshots.

| Dependency | Proposed qualification pin | Role |
| --- | --- | --- |
| Lean | `v4.34.1` | Patched stable compiler/runtime/kernel |
| comparator | `d03acab154d269c06e60e4de7e4cc85deebff94b` | Statement comparison, axiom traversal, reviewed replay/primitive-root glue |
| lean4export | `076e8e57707e813375e8f9da8bf989799ace9680` | Producer export and parser components; NDJSON 3.1.0 |
| Nanoda | `ammkrn/nanoda_lib` at `3a2407216ee84a75f9e1aead6803d0578be06ae7`, package 0.4.19 | Independent Rust proof checker |

The comparator/exporter pins declare Lean 4.34.0. The proposal is to rebuild them
under 4.34.1 with a checked-in toolchain override; that patch-version combination
has not been compiled here. Build compatibility is the first gate. Do not silently
fall back to 4.34.0 or the repository's 4.33.0 when qualification fails.

The examined current comparator/exporter heads target 4.35.0-rc3. There is no
reason to adopt that release candidate solely for the desired comparison API:
the stable comparator pin's `Main.lean` is byte-for-byte identical to the examined
head's, including quotient post-checks and primitive roots. If an actual
compatibility blocker requires another version, record it and review the new
coherent pin set explicitly. Pin transitive dependencies and preserve Apache-2.0
notices for reused components.

## What the source establishes

### Comparator has useful libraries, but the standalone executable builds source

At the selected commit, `Main.lean` always invokes `compareIt`, which builds and
exports both challenge and solution. Its internal `verifyMatch` performs the
desired checking sequence, but is embedded in the executable module and its
environment-dependent runner.

Reuse these actual APIs:

```lean
Export.parseStream : IO.FS.Stream → IO Export.ExportedEnv

Comparator.compareAt
  (challenge solution : Export.ExportedEnv)
  (theoremTargets definitionTargets primitive : Array Lean.Name)
  : Except String Unit

Comparator.checkAxioms
  (solution : Export.ExportedEnv)
  (theoremTargets definitionTargets legalAxioms : Array Lean.Name)
  : Except String Unit
```

Import `Comparator` and the export parsing library. Extract/adapt the small
`runBuiltinKernel` and primitive-root routines under their license, with a test
and upstream tracking reference for every retained rule. Do not call `M.run`,
`safeLakeBuild`, `safeExport`, or environment-selected external commands.

The official replay routine handles `Quot` specially: replay creates associated
quotient declarations, which are then compared against the export. Preserve that
post-check. Simply invoking `kernelEnv.replay` without it is not equivalent.

Latest Lake documentation also describes exported-input checking commands. Those
are distinct from the standalone executable inspected here. This design does not
depend on an unverified assumption that those latest CLI flags exist in the
selected stable toolchain.

### lean4export provides a reusable format and selected-root export

The agent invokes lean4export with module names and a list of declaration roots
after `--`. It exports the roots and transitive dependencies, including proof
bodies, opaque bodies, and required inductive groups. It does not prove anything
or authenticate its output. The verifier is equally willing to check bytes
produced by another tool.

Start with full selected-root exports. Stock lean4export has no option to omit a
pre-agreed trusted base. A delta format/exporter and persistent incremental kernel
state are later optimizations, not prerequisites for this architecture.

The SDK must include the comparator primitive roots, permitted foundational
axioms, and required quotient declarations in its export target list as well as
the submitted theorem and two candidate interpretation definitions. A theorem-only
export can omit roots which comparator deliberately requires for kernel semantics.

### The export reader needs application-level hardening

`Export.parseStream` builds Lean syntax/declaration objects through constructors;
it does not deserialize `.olean` memory images. It rejects missing references and
duplicate declaration names. It is nevertheless not a complete hostile-input
validator:

- The metadata routine reads and discards the first line, without validating the
  format or toolchain version.
- Name, universe-level, and expression tables permit duplicate indexes through
  map replacement.
- There are no application quotas on total bytes, line length, object count,
  nesting, natural-number size, expression depth, time, or memory.
- Some parsed numerical fields narrow to fixed-width integers; enforce their
  range before construction. Parsed recursor/inductive records still need checking.

Use a reviewed hardening patch to this parser, preferably contributed upstream,
with strict NDJSON metadata, complete record schemas, unique indexes including
reserved entries, reference and integer-range validation, and limits. Reject
duplicate JSON keys and trailing/unknown content. Require metadata-free expression
exports initially. Parsing does not replace kernel replay or axiom checks.

Feed the same immutable, strictly validated NDJSON bytes to both checkers. Do not
rewrite ambiguous input differently for the two implementations. A disagreement,
crash, unsupported feature, or timeout yields `UNVERIFIED`.

## How the SQL-specific adapter works

### Prepare the trusted challenge without compiling candidate code

Register approved requirements/current interpretation and their dependencies as
specified by ADR 0003. Pin their starting schema and profile. The registered
payload is checked before publication and remains under human/operator authority.
The caller selects the authorized contract ID.

For a request, the existing Python SQL frontend parses the actual schema and
migration. It passes a strict, versioned structural representation to the Lean
adapter. New `SqlLiteralExpr.lean` constructs kernel expressions directly from
those values, preserving the frontend's result-schema calculation. No candidate
Lean source is used to construct this trusted representation.

The adapter assembles a trusted challenge containing the protected library,
registered meanings, actual SQL/profile definitions, and the required theorem
type. It permits exactly two definition holes:

```text
Submission.next
Submission.failures
```

These are canonical bridge definitions for `NextInterpretation.next` and
`NextInterpretation.failures`, described below. The candidate supplies their
values. Their names, types,
universe parameters, and safety flags must match the challenge. The actual
verification-condition theorem still constrains their behavior. No holes are
permitted in Requirements, the current interpretation, admitted states, SQL,
schema, profile, or semantic library. Challenge placeholders never become trusted
axioms in the checked solution.

This preserves the existing contract about the chosen next/failure
interpretations. Replacing it with a theorem that merely asserts the existence
of some interpretation would change that binding. The existing limitation about
interpretation fidelity and arbitrary observation functions remains unchanged.

### Generate one standard bridge theorem on the agent's side

Comparator compares theorem headers structurally. The current gate instead checks
definitional equality, so an existing theorem whose type is the alias
`Generated.expected` may otherwise be rejected by comparison with an explicit
`VerificationConditions` application.

Have the preparation SDK emit `Submission.lean` with canonical bridge definitions:

```lean
def Submission.next :
    SqliteVerifier.Interpretation Requirements.LogicalState :=
  NextInterpretation.next

def Submission.failures :
    SqliteVerifier.FailureRepresentation Requirements.LogicalState :=
  NextInterpretation.failures
```

It also emits a bridge theorem named
`Submission.migrationCorrect`, whose type is the exact standard explicit
verification-condition expression using these bridge definitions and whose proof uses the existing
`Proofs.migrationCorrect`. Generate the corresponding negated bridge for a
refutation. Export the bridge and its dependencies.

The user's proof authoring interface can remain unchanged. The bridge is created
and compiled in the agent's environment and is itself untrusted evidence. The
verifier constructs the same canonical theorem header independently and checks
the bridge. A fake bridge cannot authorize a different statement.

Canonicalizing the two definition headers matters too: their original types may
be definitionally equal aliases. Require closed roots, infer the logical universe
from the protected logical-state declaration, and construct a challenge theorem
record (not an axiom record). Preserve positive-proof precedence when both source
proof names exist. These code fragments specify the adapter design; they have not
been compiled in this research.

### Check the statement, policies, and proof

The new executable performs this sequence:

1. Validate export metadata, structure, roots, resource limits, and closed root
   declarations; load the protected challenge context.
2. Compare every submitted declaration whose name belongs to the protected
   environment with its complete protected declaration record. This includes
   bodies, universes, inductive/recursor fields, and safety flags. Candidate
   interpretations and the bridge are explicitly designated submission slots,
   not protected approved definitions.
3. Invoke `compareAt` with the chosen bridge theorem plus permitted axiom roots,
   exactly the two definition holes, and the pinned primitive-root list.
4. Invoke `checkAxioms` for theorem and hole bodies. Retain the repository's
   additional explicit unsafe/partial and closed-body checks; do not assume the
   axiom traversal establishes every project policy.
5. Replay the full exported solution through the official kernel with quotient
   post-checks, and require Nanoda to accept the same bytes with the same axiom
   policy. Python invokes the fixed Nanoda binary/configuration in its existing
   sandbox; the candidate cannot provide commands or allowlists.
6. The parent reports a checked result only when the statement/policy stage and
   both kernel checks succeed. Any required process failure rejects acceptance.

Step 2 is deliberate extra glue. Comparator's generic comparison follows
statement and hole-type dependencies; a declaration used only inside a proof or
hole body need not otherwise match our protected installation. Preserve this
repository's stronger identity rule rather than assume comparator already enforces
it for all names.

The protected roots explicitly include the complete trusted declarations of all
three permitted axioms, regardless of whether the contract's type mentions them.
A name-only whitelist is insufficient: a declaration called `propext` with type
`False` must be rejected before either kernel can treat it as an assumption.

For v1, replay the complete selected-root export. Do not optimize away checks of
protected declarations independently in the two kernels until measurements show
that work matters and the resulting trusted-base protocol is reviewed.

Nanoda's verifier-owned configuration permits only `propext`, `Classical.choice`,
and `Quot.sound`; sets `unsafe_permit_all_axioms` to false and
`unpermitted_axiom_hard_error` to true; and enables its Nat/String extensions.
Do not copy its README's example allowance for `Lean.trustCompiler` or the Kernel
Arena's permit-all-axioms benchmark configuration. Forbid unrelated forbidden
axioms in the submission rather than relying on historical defaults.

Two independent implementations reduce exposure to checker-specific bugs. They
do not prove the wrapper, SQL model, parser, OS, or business specification correct.
Keep checker isolation and budgets. Run the additional checker sequentially first
under separately recorded budgets; benchmark concurrency only after measuring
memory and CPU costs. Do not silently drop it when a deadline is exceeded.

## Public interfaces and code changes

Proposed commands, not commands available in the current release:

```sh
migration-check prepare --contract CONTRACT --schema schema.sql \
  --migration migration.sql --next-interpretation NextInterpretation.lean \
  --proofs Proofs.lean --out proof.ndjson

migration-check verify-bundle --contract CONTRACT --profile 3.46.0 \
  --schema schema.sql --migration migration.sql --proof proof.ndjson
```

The trusted caller supplies the contract/profile/request arguments. The verifier
computes hashes from their exact snapshotted bytes and reports those hashes with
the proof payload digest and policy ID. Candidate-provided metadata is checked
for consistency if present, but never selects authority. A raw NDJSON file is
enough; no custom framed proof container is needed for v1.

Preserve the old source-based `verify` command as an explicitly source-executing
convenience wrapper. It retains sandboxed preparation and optional-baseline
semantics, without automatically granting registered approval. New bundle
verification has no compilation fallback. Preserve positive/refutation meaning
and all current test purposes, including installed-runtime coverage.

| Proposed implementation area | Change |
| --- | --- |
| `migration_check/prepare.py` | Run candidate build/export, generate the canonical bridge, support ordinary build caching |
| `migration_check/contract_registry.py` | Resolve immutable authorized records and snapshot them |
| `migration_check/cli.py` and `runtime.py` | Add explicit paths, bind request identities, coordinate the two checkers and results |
| `ProofDataChecker.lean` | Bounded import, protected-name comparison, comparator API calls, official replay |
| `SqlLiteralExpr.lean` | Construct trusted expressions from frontend model data; independent emitter-equivalence cases |
| Dependency parser patch | Strict metadata/schema/index/range validation and resource budgets |
| `packaging/` and Nix build definitions | Build separate preparation/checking dependencies and both native targets; prebuild parser/static library facets |

No custom kernel is proposed. File names above are design targets, not claims
that implementations already exist.

## Alternatives considered

| Component/approach | Decision and reason |
| --- | --- |
| Standalone comparator CLI | Do not wrap for acceptance: inspected implementation builds and exports source. Reuse its libraries and checking logic. |
| Official `leanchecker` alone | Logical checking alone does not establish the human-approved contract or SQL binding. Its latest exported-input mode is relevant but not a replacement for comparison and policy. |
| Nanoda alone | Useful independent kernel, but still needs statement matching, explicit axiom configuration, and input binding. Use alongside the official kernel initially. |
| Lean4Lean | Additional qualification/CI checker. Its authors note algorithmic ancestry shared with the official kernel; less implementation diversity than Nanoda. Export support is version/branch dependent. |
| con-leche | Promising checker with a consistency proof and parser-correctness work; qualify against our full corpus before making mandatory. Documented incompleteness and runtime/driver assumptions remain. |
| con-ron | Promising Rust implementation related to con-leche with refinement work; authors explicitly qualify the assurance of its translation/driver. Additional qualification candidate. |
| Lean Kernel Arena | Reuse relevant hostile-proof fixtures and comparison methodology. Its benchmark allowlists, patches, and failure classifications are not production policy. |
| Full delta export / cached kernel state | Defer until full-export checking is measured. Stock exporter does not provide this interface. |
| SNARK or zkVM receipt | Defer. It could move even proof checking to the agent, but adds a new prover and cryptographic trust/cost model. No project latency evidence justifies it yet. |

All selected upstream components are Apache-2.0; preserve notices and review
transitive packaging licenses. Published whole-Mathlib checker timings are not
predictions for these SQLite proofs and are not used as a latency promise.

## Implementation gate and next experiment

First build the exact qualification pin set on Linux and macOS. Then prepare and
check the small invoice example, allowed-failure example, Atuin example, and a
kernel-checked refutation through NDJSON. Verify the bridge, exact two holes,
approved-schema binding, and all protected primitive declarations. Test altered
SQL, weaker requirements, a wrong proof, `sorry`, forged recursors/quotients,
changed types of permitted axioms, duplicate indexes, format mismatches, and
truncated/oversized inputs. Include definitionally equal aliases in both theorem
and interpretation signatures to validate the canonical bridge compatibility.

Instrument source preparation, export, transfer size, validation/comparison,
official kernel, Nanoda, peak memory, and total time. Acceptance must invoke no
compiler/exporter. Preserve existing tests and test limits; any budget adjustment
requires reported measurements. If a second checker cannot handle a supported
case, investigate/fix or revise the proposal explicitly; do not accept with only
the other checker silently.

The development environment here has no Lean, Lake, Nix, or Rust toolchain, so
this report establishes interfaces and source-level feasibility, not a successful
integration build. The proposal resolves the component selection; the experiment
above verifies that those selected components work together for our workload.

## Primary sources

- [Comparator stable Main/replay](https://github.com/leanprover/comparator/blob/d03acab154d269c06e60e4de7e4cc85deebff94b/Main.lean),
  [comparison](https://github.com/leanprover/comparator/blob/d03acab154d269c06e60e4de7e4cc85deebff94b/Comparator/Compare.lean),
  [axiom traversal](https://github.com/leanprover/comparator/blob/d03acab154d269c06e60e4de7e4cc85deebff94b/Comparator/Axioms.lean).
- [Exporter format](https://github.com/leanprover/lean4export/blob/076e8e57707e813375e8f9da8bf989799ace9680/format_ndjson.md),
  [parser](https://github.com/leanprover/lean4export/blob/076e8e57707e813375e8f9da8bf989799ace9680/Export/Parse.lean),
  [CLI/export documentation](https://github.com/leanprover/lean4export),
  [Nix static-facet issue](https://github.com/leanprover/lean4export/issues/40).
- [Lean 4.34.1 release notes](https://lean-lang.org/doc/reference/latest/releases/v4.34.1/),
  [proof-validation guidance](https://lean-lang.org/doc/reference/latest/ValidatingProofs/),
  [latest Lake interfaces](https://lean-lang.org/doc/reference/latest/Build-Tools-and-Distribution/Lake/).
- [Nanoda configuration](https://github.com/ammkrn/nanoda_lib),
  [selected version/license](https://github.com/ammkrn/nanoda_lib/blob/3a2407216ee84a75f9e1aead6803d0578be06ae7/Cargo.toml).
- [Lean4Lean](https://github.com/digama0/lean4lean),
  [con-leche](https://github.com/leanprover/con-leche),
  [con-ron](https://github.com/leanprover/con-ron),
  [Kernel Arena](https://github.com/leanprover/lean-kernel-arena).
