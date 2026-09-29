# ADR 0002: Optional local caching inside compile_project()

- Status: Proposed; cache disabled by default throughout initial rollout
- Date: 2026-09-26
- Repository examined: `54ea013ab12d16fdc35d9b08bd26078c24c547aa`
- Decision owner: formal methods / technical lead
- Related: [ADR 0001](adr-0001-pytest-and-nix-ci.md)

## 1. Observed pain

The test suite runs many separate verifier processes, including several cases
using the same starting schema and approved definitions. A developer rerunning a
case has no option to reuse compilation work from the preceding invocation and no
stage-level report showing which part of verification consumed the time.

The Atuin command has a 1500-second suite timeout, while the historical performance
report records an installed run of 113.45 seconds in one local environment. Neither
number tells us how much time recompiling unchanged inputs contributes. The visible
problem is slow, poorly explained repeated verification; the likely benefit of a
compilation cache still needs measurement.

## 2. Goals

Reduce the elapsed time of repeated verification when the starting schema,
approved definitions or generated SQL inputs remain unchanged. This should improve
developer iteration and repeated test runs in which the cache is explicitly enabled.
The first release targets local reuse between CLI invocations, not remote reuse
of successful verification results.

Make that improvement explainable: report time spent discovering sources,
compiling each stage and running the kernel gate, together with cache hits,
bypasses and their costs. A warm run should avoid eligible compiler invocations
and improve complete verification time after lookup, hashing and copying are included.

The result must still correspond to the current supplied inputs and approval
baseline. Candidate compilation and the independent kernel gate must execute
freshly on every verification that reaches those stages. Unsupported or unusable
cache inputs must leave an ordinary uncached verification path available. These
are correctness constraints on the optimization, not performance tradeoffs.

No numerical speedup is promised before stage timings establish the opportunity.
The default and required acceptance runs remain uncached during the initial rollout.

## 3. Investigation and root causes

### 3.1 Repeated processes do not retain compilation work

Inspection of `cli.py` shows that each verification creates a temporary workspace
and calls `compile_project()`. The compilation function requires that workspace to
be empty. It discovers source closures and invokes the compiler in separate
sandboxes; the artifacts belong to that verification's private workspace.

As a result, a later CLI invocation recompiles unchanged stages when it reaches
them. This behavior is deliberate isolation, but it is also a concrete source of
repeated work. A cache around the project's Lake build does not reach these dynamic
compiler invocations inside the running verifier.

### 3.2 The existing stages expose a possible reuse boundary

`source_closure.py` invokes the pinned compiler with `--deps-json` to discover
imports. `compile.py` then compiles modules in fresh sandboxes, in this order:

| Stage | Inputs visible in the current implementation | Output destination |
| --- | --- | --- |
| Schema | `SchemaInputs.lean`, runtime libraries | `schema-output/` |
| Approved | Approved source snapshots, schema artifacts, preceding approved outputs, runtime | `trusted/` |
| SQL | `SqlInputs.lean`, sibling generated source files, schema artifacts, runtime | `sql-output/`, then copied into `trusted/` |
| Candidate | Candidate snapshots including `Generated`, complete trusted artifacts, preceding candidate outputs, runtime | `candidate/` |

The selected source files are sealed before elaboration. Baseline comparison
already happens after closure discovery and before compilation. The existing
`early_baseline_test.py` checks that ordering and snapshot behavior.

### 3.3 Reuse requires more than source and import hashes

Lean elaboration can execute code. The sandbox exposes more than the declared
import graph: it includes source directories and preceding artifact directories,
and allows nondeterministic facilities such as randomness. Source text and direct
import names alone therefore do not determine an arbitrary compilation's behavior.
Caching also suppresses execution of elaboration-time effects.

In addition, a perfectly type-correct `.olean` can encode a different approved
contract from the supplied source. The kernel checks logical correctness; it does
not establish that a cached binary came from those source bytes. Our checker
replays declarations from generated, approved and candidate modules, but provenance
of cached approved artifacts still depends on the cache writer and lookup policy.
Checksums inside a writable cache are not authentication against a malicious writer.

The investigation therefore identifies two separate requirements for reuse:
compilation must depend only on the identified inputs, and a restored artifact must
come from the trusted compilation of those inputs. Kernel replay remains necessary
but does not establish the second requirement by itself. See
[the current checker](../ProofChecker.lean), particularly `importData`, `additions`,
and `checkProof`.

### 3.4 What the investigation has not established

The code establishes that compilation work is repeated. It does not establish
that eligible stages dominate runtime, that every approved source is deterministic,
or that restoring their artifacts is cheaper than compiling them. In particular,
header discovery and kernel replay would remain even with perfect compilation
cache hits. Treating all elapsed test time as recoverable would overstate the benefit.

The current [CI policy](ci.md) also requires fresh source elaboration and proof
checks. Reusing compilation inside the verifier changes that execution policy for
the enabled stages and needs its own decision; it is distinct from caching fixed
project build outputs under [ADR 0001](adr-0001-pytest-and-nix-ci.md).

## 4. Assumptions and how to challenge them

### 4.1 Hypotheses behind the optimization

These assumptions explain why this cache could achieve the goals. Establish the
performance assumptions with measurements and challenge the semantic assumptions
with code review and adversarial examples. Passing a finite set of tests does not
prove that an arbitrary Lean elaborator is deterministic.

| ID | Assumption | Evidence that would falsify or materially weaken it | Response |
| --- | --- | --- | --- |
| A1 | Repeated eligible compilation accounts for a useful share of verification time | Stage timings show most time is in discovery, candidate compilation or the gate | Narrow or defer the cache and optimize the measured bottleneck |
| A2 | Generated stages and specifically reviewed approved closures behave deterministically under identified inputs | Same identified inputs produce different meanings or depend on time, random data, paths or undeclared mutable state | Remove eligibility; expand the identity only if the dependency can be bounded, otherwise compile freshly |
| A3 | Useful workloads repeat eligible identities often enough to get hits | Real edit/retest sequences almost always change the runtime, schema or qualified closure | Reconsider the stage boundary or scope; do not widen eligibility merely to improve hit rate |
| A4 | Lookup, validation and copying cost less than the avoided compilation | Complete warm runs are no faster, or slower, despite hits | Leave the expensive stage bypassed and retain timing evidence |
| A5 | Private restored artifacts remain tied to current qualified inputs and cannot be replaced by proof code | A mutation, hostile path or sandbox escape makes an incompatible artifact reusable | Block rollout and fix the provenance or containment failure |
| A6 | Reuse preserves observable verification behavior and artifact relocation | Cold and warm runs disagree on status, current input hashes, stable diagnostics or imported meaning | Disable the affected stage; investigate before broadening reuse |

A cache with a high hit rate can still fail A4. A cache that is fast can still fail
A2, A5 or A6. Both performance and correctness evidence are required.

### 4.2 Trust and deployment preconditions

The following are explicit boundaries of the solution. If the intended deployment
cannot satisfy them, this design does not apply; successful benchmarks cannot
compensate for a missing trust boundary.

- The verifier installation, immutable Nix runtime, parent process, and host account
  are trusted. A hostile process with unrestricted access as the same host user
  is outside the existing sandbox threat model and this cache's threat model.
- Candidate and approved source programs may be hostile inside the proof sandbox.
  They must not read or write the cache, eligibility registry, or signing secrets.
  This design uses no cache signing secret and accepts no remote cache imports.
- Only the verifier parent writes cache records after existing artifact validation.
  Candidate paths, `.olean` files beside source inputs, and candidate manifests
  never supply cache records or eligibility decisions.
- V1 requires the selected `sysroot` and project library to be immutable store
  outputs produced by the build design in ADR 0001. Mutable Elan installations,
  ad hoc local `.lake` builds and mutable installed payloads bypass the cache.
  Verification still works there. Supporting those runtimes is a separate extension.

## 5. Proposed architecture

### 5.1 Reuse selected compilation stages through the trusted parent

Add an optional local cache owned by the verifier's parent process. The parent
still snapshots the current inputs, discovers both source closures and checks any
supplied approved baseline. Only after those checks may it consider cached work.

For an eligible stage, the parent constructs an identity covering the sealed source
set, predecessor artifacts, runtime and compilation policy. On a valid hit, it
copies validated artifacts into the new verification's private workspace. On a miss
or bypass, it compiles the stage using the existing sandbox and may publish its
validated output. Subsequent compilers and the kernel gate see private copies,
not the cache directory.

This preserves the existing private-workspace boundary while allowing selected
work to survive between CLI processes. It addresses A3 without requiring a
long-lived verifier service. Complete stage records keep the first implementation's
dependency and publication rules simpler than a cache of individual modules.

### 5.2 Eligibility determines the extent of reuse

| Stage or operation | Proposed behavior | Reason |
| --- | --- | --- |
| Input snapshot, closure discovery and baseline check | Execute freshly | Establish which inputs the current request supplies and whether they are approved |
| Generated SchemaInputs and SqlInputs | Eligible after template/runtime qualification | Their source construction is verifier-controlled |
| Entire approved compilation stage | Eligible only for an exact separately reviewed deterministic closure and runtime | Business approval alone does not imply deterministic elaboration |
| Candidate compilation | Execute freshly | Arbitrary candidate elaboration is outside initial eligibility |
| Independent kernel gate | Execute freshly | Every accepted request still needs its current proof checked |

Start with generated stages. Add the Atuin approved closure only after reviewing
its elaboration dependencies and recording an explicit qualification. The approved
registry starts empty. Unrecognized, modified or unqualified source closures use
normal compilation; a matching user baseline cannot grant cache eligibility.

This restriction follows from A2 and A5. It intentionally limits the possible
speedup until we have evidence that a useful larger stage can be reused safely.

### 5.3 Failure handling and measurement are part of the design

Cache records represent successful qualified compilation, not proof acceptance.
Failures and timeouts create no reusable stage entry. Invalid, incomplete or
unusable cache records lead to uncached compilation. The parent alone validates
and publishes records; hostile proof programs cannot supply their own entries.

An optional timing report separates discovery, compilation and gate work from
cache hashing, lookup and copying. It makes A1, A3 and A4 testable and explains a
bypass instead of making the cache an opaque performance feature. The JSON
verification result retains its existing meaning.

### 5.4 Scope and alternatives

Cache enabled stages only after explicit local opt-in. Required CI acceptance and
mutable installed runtimes remain uncached initially. The cache is not distributed
through ADR 0001's Nix or Actions cache. If accepted, document this limited exception
to [CI policy](ci.md) and the
[earlier performance task](../plans/20260925-ci-performance.task.md).

A generic source/import-hash cache would not address the identified elaboration
and provenance problems. Caching final verdicts would omit required fresh checks.
Lake, Nix or Bazel can reuse fixed build tasks but would need explicit integration
to reach the work inside `compile_project()`. A process-local cache would lose its
contents between the separate CLI invocations that motivate this proposal.

Per-module caching, qualified candidate-stage reuse, remote cache imports and Lean
incremental snapshots are possible later designs. Each adds dependency or trust
questions; stage measurements should establish their value before that expansion.

## 6. Implementation and migration

Implement instrumentation first, then storage and generated-stage reuse, and only
then any qualified approved-stage reuse. The following contracts make those steps
concrete; the work-package table specifies which evidence permits progression.

### 6.1 Qualification and exclusions

The technical lead reviews generated templates and the exact approved closure,
including macros, tactics, module initializers and imported runtime code used
during elaboration. Eligible code must not depend on time, randomness, absolute
workspace names, mutable host files, directory enumeration outside the declared
input set, resource-sensitive branching, or externally observable elaboration effects.
Qualification applies to the fixed compiler/runtime identity, not just source text.

Create a verifier-owned `cache_eligibility.py` registry whose approved entries bind:
policy revision, full module-name/source-hash map, supported toolchain/library
identity, and a link to the review record explaining why the closure is eligible.
It is loaded from the trusted verifier installation. User baseline files cannot
add entries. Any source, membership or runtime change requires a matching newly
reviewed entry; otherwise the approved stage is an ordinary cache bypass.

Review the current Atuin closure (`Requirements`, `Interpretation`, `SchemaBinding`,
`HistoryModel`, `HistoryDecoding`, `HistoryMapping`) as a candidate, not as implicitly
approved for caching. Business approval and determinism qualification are separate.
Qualifying it must not edit protected example bytes just to obtain a cache hit.

A lexical search for `IO`, `unsafe` or `run_elab` is only a review aid, never the
qualification algorithm. An imported tactic can introduce those effects indirectly.
Empirical agreement between two runs does not prove determinism.

Do not cache source discovery, baseline decisions, candidate compilation, failures,
timeouts, kernel results, `VERIFIED`/`VIOLATED` reports, or arbitrary module prefixes
from failed compilation stages. Do not use Lean incremental environment snapshots,
pickle, external `.olean` downloads, or a caller's Lake cache as substitutes.
Stage-level caching is intentionally conservative; finer module caching is deferred.

### 6.2 API and observable behavior

Add an optional keyword to `compile_project()`:

```python
cache: CompilationCache | None = None
```

`None` retains the current code path. Keep the existing `CompiledProject` fields
and source hash meanings. Supply performance events through a separate optional
collector, not through the semantic input manifest.

CLI additions (mutually exclusive cache options):

- `--compile-cache PATH`: request a private local cache at this path.
- `--no-compile-cache`: explicitly disable caching; equivalent to the default.
- `--timings PATH`: optionally write structured stage timings/cache counters.

No ambient environment variable silently enables reuse, including under the
installed isolated launcher. With a cache requested, unsupported runtime or source
eligibility produces `bypass` and normal compilation. An unsafe/unusable root also
produces a bounded stderr diagnostic and uncached execution without touching it.
Do not convert a cache miss into a user-input failure or a successful verdict.

Keep JSON stdout compatible. Put cache warnings on stderr and optional measurements
in the timings file. Store only bounded reason codes, not complete user sources,
in that report. Suggested fields: `schema_version`, runtime ID, stage name,
`hit|miss|bypass|corrupt`, reason, lookup/hash/copy/compile milliseconds, compiler
process count, bytes read/written, and kernel milliseconds/invocation count.

### 6.3 Cache identity

Use SHA-256 of canonical UTF-8 JSON (`sort_keys=True`, compact separators, no
floats) for each stage key. Hash raw source bytes separately; never normalize
whitespace or Lean text. Sort sets by exact module/path name and preserve import
search precedence and actual compilation order where order is meaningful.

| Field | Requirement |
| --- | --- |
| Format/policy | Explicit cache-format and eligibility-policy revisions |
| Stage | Distinct `schema`, `approved`, `sql` namespaces |
| Runtime | Native OS/architecture, exact immutable Lean sysroot and library store identities, declared loader closure, system runtime epoch |
| Compiler contract | Semantic command flags, import search order, sandbox policy identity, relevant compiler/generator/source-closure implementation hashes |
| Sources | Complete stage-visible source snapshot map, including filenames, module names, and raw-byte hashes |
| Predecessors | Digests of the complete validated predecessor artifact manifests, including all file hashes and sidecar membership |
| Qualification | Trusted registry entry ID for approved stages; generated-template qualification ID for generated stages |

The system runtime epoch must include host OS build/kernel identity and known
platform loader metadata (for example macOS build version), because current
sandboxes expose system libraries outside the Nix store. Eligibility forbids
reading arbitrary mutable host files. If a relevant runtime dependency is unknown,
disable reuse rather than guessing its identity. Do not claim that an OS name alone
models all host behavior.

For v1, use whole-stage keys:

- **Schema:** actual schema-generated source plus runtime/compiler identity. At this
  stage, do not expose a later `SqlInputs` source by moving writes earlier.
- **Approved:** entire approved source closure and its membership, the actual
  `SchemaInputs` artifact manifest, runtime identity, approved compilation order,
  and eligibility ID. Hash the entire closure, not just the module being compiled.
- **SQL:** actual SQL-generated source, sibling schema-generated source, actual
  schema artifacts, and runtime identity. The execution profile occurs in the
  generated SQL source; a changed profile must invalidate it.

Changing only candidate proof text must not invalidate schema or approved entries.
Changing an approved transitive dependency must bypass qualification until reviewed
and must never select the old approved entry. The baseline file itself is checked
fresh and does not become a shortcut in the key. Raw schema approval bytes remain
checked even if two SQL inputs generate identical Lean source.

Temporary physical workspace paths are omitted only because qualified code must
be path-independent. Preserve relative module names and import order. Validate
relocation with real Lean tests before enabling any entry. If Lean artifacts or
diagnostics cannot be relocated safely, bypass that stage rather than reuse it.
V1 caches only successful stages with empty compiler diagnostics, avoiding replay
of stale source paths/warnings; uncached runs keep existing diagnostics behavior.

### 6.4 Store format and lifecycle

Use `ROOT/v1/PLATFORM/STAGE/KEY/`, with a manifest and an `artifacts/` directory.
Create the root explicitly with mode 0700. Verify ownership and no group/other
write access; reject symlinks in cache-controlled path components. Shared writable
cache roots are unsupported. Do not place the cache below any proof-readable input
or runtime root, or make it an ancestor of those roots. Check this against actual
sandbox bindings before use, not only the originally supplied source paths.

The manifest contains format/stage/key, complete canonical key material, and the
exact list of module-relative artifact paths, sizes and SHA-256 digests. Eligible
suffixes are those currently copied by `compile_modules()`:
`.olean`, `.olean.server`, `.olean.private`, `.ir`, `.ir.sig`. Every compiled module
requires `.olean`; optional sidecars are recorded with exact presence/absence.
Do not infer required sidecars from a different Lean release.

On reads, use descriptor-based no-follow operations and verify regular files,
ownership, link count, bounded size and containment before reading bytes. Reject
absolute paths, traversal, duplicate names, case-fold collisions and unexpected
files. Apply `module_path()` semantics for escaped module names. Hash the bytes
actually read into the private staging copy; do not validate one path and later
copy it through an unchecked lookup. No compiler runs against the cache directory.

V1 limits: manifest at most 1 MiB, at most 4096 artifacts per entry, each artifact
at most the existing 16 MiB compiler file limit, at most 256 MiB per entry, and
1 GiB published data per cache root. Stream large files. Oversized/unreadable entries
are misses; exceeding the publication budget skips a write. These cache limits
must not lower the verifier's existing input acceptance limits. Reuse the resource
preflight for the actual cache volume before writes. Do not add automatic eviction
or garbage collection. Document removing only a user-selected cache directory
while no cache clients are using it.

#### Publication and concurrency

1. Obtain a bounded per-key writer lock (POSIX `flock` works on both supported
   platforms), recheck the entry, and do not wait more than five seconds. A lock
   timeout means compile privately and skip publication.
2. Compile in the existing private workspace and validate emitted artifacts through
   `artifact_bytes()`. Never publish directly from a compiler-owned directory.
3. Copy validated bytes into an exclusively created sibling temporary entry owned
   by the parent. Write and flush files and manifest; fsync before publication.
4. Atomically rename into the final key while holding the lock. Readers see either
   a complete entry or a miss; they ignore temporary entries. If a valid entry
   already exists, use it and discard only the current writer's temporary entry.
5. For root-budget accounting, use a short root lock while publishing; do not hold
   it during compilation. Count staging bytes in the resource preflight. If locking
   or capacity is unavailable, skip publication.

Corrupt entries are reported and ignored, then the stage recompiles. Under the key
lock, move a corrupt entry out of the active namespace to a uniquely named
quarantine location before publishing a replacement. Count quarantine data toward
the root budget; never follow its links or delete unrelated files. Crashes may leave
temporary/quarantine entries; they never constitute hits. Cache I/O failures must
not hide compiler errors or change verification outcomes.

### 6.5 Integration algorithm

Refactor preparation from execution only as far as needed to represent three
eligible stage descriptors. Preserve existing snapshot and error ordering.

```text
validate runtime and require an empty private workspace
snapshot SQL and selected Lean inputs as today
discover both approved and candidate closures as today
compute current source hashes and compare optional baseline
for schema, approved, sql in the existing order:
    write exactly the stage's current generated sources
    calculate qualification and identity from sealed inputs
    if eligible and cache requested, validate and privately restore a hit
    otherwise compile the full stage with existing sandbox/artifact checks
    optionally publish a complete successful eligible stage
assemble trusted outputs as today
compile candidate stage freshly
return current hashes and private artifact paths
CLI always invokes the independent kernel checker
```

No lookup, cache-root creation, or manifest parsing is permitted before a supplied
baseline has passed. Header-discovery errors retain precedence over baseline
errors. A hit copies fresh ordinary files into the current private destination;
never return cache paths, symlinks or hardlinks as `CompiledProject` outputs.
The gate and subsequent compilers receive only those private copies. Include
tests proving candidate code cannot see cache manifests or other entries.

A cached schema/approved stage may have been produced during a verification whose
candidate was later rejected. That is acceptable: the cached record asserts only
successful qualified compilation. Final acceptance still requires the current
candidate's fresh compilation and gate result. Never interpret the cache record
as approval, proof validity, or a reusable positive outcome.

### 6.6 Work packages

| Step | Files / responsibility | Depends on | Deliverable and reviewer gate |
| --- | --- | --- | --- |
| K0 | Timing collector around discovery, baseline, each compilation stage and gate; optional `--timings` in `cli.py` | None | Cold measurements with no caching; unchanged outcomes/output contract |
| K1 | `compile.py` stage descriptors and canonical manifest/key helpers in new `compilation_cache.py` | K0 | Unit tests for dependency invalidation; cache still disabled |
| K2 | Cache-root validation, read/write protocol, limits and locks | K1 | Filesystem/concurrency adversarial tests; independent security review |
| K3 | Generated-stage qualification and cache integration; immutable runtime identity from ADR 0001 builds | K2, ADR 0001 B1/B2 | Real cold/warm runs on both platforms, fresh candidate and gate spies |
| K4 | `cache_eligibility.py`, Atuin approved-closure audit and review record | K3 | Formal methods lead signs off exact closure and runtime; changed source bypasses |
| K5 | Enable approved-stage cache only for that reviewed entry; docs and benchmarks | K4 | All old adversarial cases agree with cache off; measured net gain |
| K6 | Optional developer opt-in release; separate non-required CI cache experiment | K5 | Default acceptance and installed tests still uncached; clear rollback |

Junior implementers own storage, instrumentation, fixtures and plumbing. They must
not decide determinism qualification or alter replay/import policy without the
formal methods lead's review. Pair a different reviewer with each storage and
trust-boundary change. Implementers should stop an affected step and report a
concrete counterexample if qualification or cache containment cannot be established;
the uncached path remains usable.

### 6.7 Required acceptance tests

Use the case conventions from ADR 0001. Table rows are independently selectable
test families with descriptive parameter IDs. Filesystem tests use tiny fixtures;
semantic claims require real Lean and the actual kernel checker.

| Family | Required observation |
| --- | --- |
| Disabled path | No cache directory created/read; all current tests and statuses unchanged |
| Warm qualified hit | Eligible compilation subprocess count decreases; candidate compile count and gate invocation count remain nonzero on every verification |
| Fresh snapshots | Mutate original source/schema files after snapshot; both warm and cold runs use the same sealed bytes |
| Baseline precedence | Warm cache plus changed/invalid baseline yields INPUT_ERROR before lookup or compilation; missing imports still fail at discovery |
| Key invalidation | Change schema, SQL, profile, approved dependency/membership, compiler flags, library/sysroot, sandbox policy, registry revision and sidecar bytes independently; never hit an incompatible entry |
| Candidate-only change | Preserve eligible upstream hits, compile altered candidate freshly, reject stale/unfinished/forged proof exactly as before |
| Unqualified code | Randomness/path/IO-dependent approved elaborator and any changed closure bypass approved caching, even if baseline-approved |
| Relocation | Same qualified inputs in different workspace names, including spaces/Unicode, retain correct status and imports on both platforms |
| Corruption | Truncation, malformed/oversized manifest, missing required/recorded sidecar, altered digest, extra file: miss and safe recompilation |
| Hostile paths | Symlinks at each level, hardlinks, FIFO/device, traversal, case collisions, unowned/shared root: no unsafe read/write and no hit |
| Crash/concurrency | Two writers, reader during publication, killed writer, lock timeout, disk-full simulation: complete hit or miss, no partial import and no deadlock |
| Sandbox boundary | Hostile Lean code cannot read/write the cache or another proof's artifacts; existing sandbox tests still pass |
| Artifact provenance | A forged but logically valid weaker approved artifact cannot be supplied via candidate/source directories as a cache entry |
| Gate remains decisive | Force checker failure after a cache hit and assert the verifier does not report VERIFIED; all initializer/axiom/replay attacks remain rejected |
| No negative caching | Timeout, incomplete compilation and compiler failure create no reusable stage entry |

Also test a forged artifact and self-consistent forged manifest inside a deliberately
untrusted cache root. The root must be rejected; this demonstrates why checksum
validation alone is insufficient. Do not claim detection of arbitrary malicious
rewrites by a trusted host account in its own valid private cache.

Use the full thirteen-case Atuin source suite, ordinary CLI, early-baseline,
compilation and kernel suites as differential acceptance: cache off, empty cache,
warm cache. Compare status, exit code, approved/source hashes and stable diagnostics.
Do not require identical temporary paths or timing text. Always run the installed
suite uncached as well; mutable installed runtime caching is outside v1 scope.

### 6.8 Benchmark, rollout and rollback

Report conclusions against section 4's assumptions: stage times for A1, qualification
review and counterexamples for A2, realistic edit/retest hit rates for A3, total
warm elapsed time for A4, hostile-input tests for A5, and differential outcomes
for A6. Distinguish a failed implementation contract from a workload assumption
that measurements show was wrong.

Before K3 and K5, measure the same native runtime and revision with cache off,
empty cache, and warm cache. Use at least three runs of each on Linux and macOS.
Record runtime/host identities, qualification IDs, source case IDs, stage compiler
counts, header processes, bytes hashed/copied, lookup/lock/compile/gate time, disk
use and complete suite time. Include changed SQL, changed proof, and changed
approved source runs. Clear only an experiment-owned cache between cold trials.

Do not promise that generated-only caching will materially improve total runtime.
The Atuin approved stage may offer greater reuse, but that is a hypothesis until
K0 measurements and K4 qualification. If hashing/copying costs exceed compilation
savings, leave that stage bypassed and retain the measurements. Gate time and
header-discovery time remain even on a perfect cache hit.

Release only as opt-in after both-platform correctness and performance evidence.
Required CI runs keep `--no-compile-cache`; an additional experiment may use a
fresh job-local directory for a cold/warm comparison. No Actions cache path or Nix
derivation may distribute these entries. Turning caching on by default, accepting
external entries, or expanding eligibility requires a follow-up ADR and product
owner/technical-lead review of the changed assumptions.

Rollback is removing `--compile-cache` or disabling the eligibility registry. Cache
format changes use a new namespace; old entries are ignored without automatic
deletion. No user SQL, approved source, proof file or approved-baseline manifest
is modified by this feature.

## Research references

Consulted 2026-09-26. The design is derived primarily from the repository's pinned
code, not a claim that the latest Lean documentation proves cache safety.

- [Compilation, snapshots and artifact validation](../migration_check/compile.py)
- [Closure discovery and compiler sandbox inputs](../migration_check/source_closure.py)
- Sandbox policy and process cleanup (`migration_check/sandbox.py`, removed 2026-09-29)
- [CLI verification and fresh kernel invocation](../migration_check/cli.py)
- [Independent replay and target reconstruction](../ProofChecker.lean)
- [Existing early-baseline regression](../tests/early_baseline_test.py)
- [Lean build tools and checker overview](https://lean-lang.org/doc/reference/latest/Build-Tools-and-Distribution/)
- [Lean module semantics](https://lean-lang.org/doc/reference/latest/Source-Files-and-Modules/)
- [Lean module initializer behavior](https://lean-lang.org/doc/reference/latest/Run-Time-Code/Foreign-Function-Interface/)
- [Nix filesets for explicit build inputs](https://nix.dev/tutorials/working-with-local-files.html)
- [Bazel's explicit action input model](https://bazel.build/remote/caching)

The phase-key schema, eligibility restrictions, storage limits and rollout gates
are project design decisions proposed here, not guarantees supplied by those tools.
