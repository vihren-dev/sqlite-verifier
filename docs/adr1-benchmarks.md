# ADR 0001 native benchmark protocol

Historical protocol: the unit-cache/coverage rollout described here was
superseded on 2026-09-28 by [Nix test targets](../build-support/README.md).
The owner removed the benchmark workflows, `tools/benchmark_*.py`,
`tools/cache_fingerprint.py` and `tests/case-inventory.json` on 2026-09-29; this
page only records the earlier protocol and its results.

The build-output cache remains experimental. `ci.yml` defaults to the dependency
cache and checkout build. A manual experimental CI input, or a pull request branch
starting `experiment/adr-0001-`, exercises the candidate graph while retaining the
same fresh host acceptance and release gates.

The separate `ADR 0001 native benchmark` manual workflow runs only on main.
Do not dispatch it until source and installed acceptance pass on both native
platforms. It does not enable rollout or publish releases. After review, an
operator may dispatch it from the default branch; no repository variable is needed.

The matrix contains 60 fresh native jobs: two implementations, two platforms,
three repetitions and five scenarios. Baseline source is pinned to optimized
revision `7a99c71f40c66077b2293e1ce2c8ef3151ce5d67`; candidate source is the
workflow revision. Linux uses ubuntu-22.04 and Darwin uses macos-14. The cold
jobs seed isolated run/attempt/implementation/platform/repetition cache namespaces.
Repetitions run one at a time: each completes its four cold jobs and sixteen
restored jobs before another repetition starts. At most four active cache seeds
must coexist; caches from completed repetitions can be evicted safely.
Benchmark invocations share one concurrency group, with cancellation disabled,
so two experiments cannot compete for their active seeds.
Only successful main cold jobs save. Each later job starts on a fresh runner and
restores its matching seed; no garbage collection or cache purging runs.

| Scenario | Cache state | Fresh work |
| --- | --- | --- |
| cold | No experiment cache | Complete source acceptance |
| warm | Matching seed | Complete source acceptance |
| python | Matching seed, changed Python test comment | Complete source acceptance |
| lean | Matching seed, changed Lean source comment | Complete source acceptance |
| package | Matching seed | Complete source and installed package acceptance |

Controlled comments change `tests/test_translation.py` or
`SqliteVerifier/Model.lean`. Each sample records before/after hashes and the exact
revision. Baseline recipes remain unchanged. Candidate recipes receive immutable
runtime and unit-check roots, validate current unit identities before reuse, and
run proof, conformance and sandbox acceptance freshly on the host.

Artifacts retain sample metadata, command logs, phase timing/status, actual
Lean/Lake/Python/Nix versions, runner image metadata, source/installed JSON and
JUnit, case failure diagnostics and separately identified cached unit receipts.
The legacy baseline predates per-case receipts: its original suite logs and
aggregate correctness gate remain authoritative. A legacy-to-node mapping is
retained for comparison; it is not evidence that modern node IDs ran in baseline.
Baseline per-case timings are explicitly unavailable.

The collector retrieves completed GitHub job timestamps and raw logs, including
post-action cache saving. End-to-end times therefore include checkout, Nix/cache
setup, build, tests, artifact upload and cache saving. Cache restore/save step
times remain separate. Actual cache archive bytes are extracted only when action
logs report them; an empty list means unavailable, never zero bytes transferred.
Disk usage is sampled once per second on workspace, temporary and Nix filesystems
through the final cache post hook; peaks and minimum available space are reported
per filesystem and are not summed when paths share a volume. This is sampled
filesystem usage, not a claim of exact instantaneous process disk allocation.

`summary.json` requires all 60 unique successful samples, expected restored-key namespace, disk observations and exact passing candidate
case receipts. Fresh source IDs plus cached unit IDs must equal the source
catalogue without duplicates; source receipts must match the current coverage
run UUID. Package receipts must match the 19 installed IDs in the current
inventory. It compares medians per platform/scenario. Warm
candidate time must improve on baseline. The draft material-cold-regression
threshold is at most 10% median slowdown; this is an explicit review assumption,
not a change to the accepted ADR. Changed-input and packaging timings are retained
for review even though no additional numeric threshold is invented for them.

A passing recommendation still has `rollout_enabled: false`. Review the raw
correctness reports, source selection, disk peaks, transfer costs and medians
before approving normal build-cache use. Missing logs, failed jobs, skipped cases
or incomplete metrics prevent a passing recommendation. Native execution and
GitHub post-hook integration remain pending until this workflow is integrated.

The pinned cache action's [output contract](https://raw.githubusercontent.com/nix-community/cache-nix-action/7df957e333c1e5da7721f60227dbba6d06080569/action.yml)
includes primary and prefix matches in its hit signal; the collector additionally
checks the actual restored key. Before the full matrix, dispatch with `pilot: true` to validate logs retrieval,
artifact paths and disk post-hook output. Pilot selects only candidate repetition
one on both platforms, cold then warm: four native jobs. All correctness gates
remain active. Its summary deliberately fails the unchanged 60-sample readiness
gate; that comparison step is allowed to fail so its raw evidence can be inspected.
Pilot cannot authorize rollout. The default `pilot: false` retains all 60 jobs.

Within a repetition, up to four cold jobs or twelve restored jobs run concurrently.
Pilot 36410934815 measured candidate seeds of 1,731,976,808 bytes on Linux and
1,780,962,687 bytes on Darwin. Six candidate seeds alone would occupy
10,538,818,485 bytes, before the six baseline seeds. The repository's verified
cache limit is 10 GB, so an all-cold-before-all-restored matrix would risk eviction
of required seeds. The native reusable-workflow grouping retains the same sixty
fresh VMs, scenarios and correctness gates; it changes scheduling only. GitHub
may queue macOS jobs above the account's platform limit. Actual runner timings
and image metadata remain the comparison evidence.
