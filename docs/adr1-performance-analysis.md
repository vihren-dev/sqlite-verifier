# ADR 0001 performance root-cause analysis

Date: 2026-09-28. Evidence: completed repetitions one and two of
[benchmark 36414706819](https://github.com/vihren-dev/sqlite-verifier/actions/runs/36414706819).
The third repetition is still running. This report does not replace the full
[benchmark acceptance](adr1-benchmarks.md) or authorize rollout.

The largest identified increase is inside **fresh checks**. The migration added
140 freshly executed infrastructure cases and three full CLI verifications.
Restoring a larger Nix archive and resolving its package source add further cost.
The cache does restore and reuse the intended project outputs; cache correctness
has not translated into lower end-to-end time in these completed warm samples.

## Where the warm-run increase occurs

These are completed native job times, including cache post hooks. Each row pairs
the same platform and repetition on separate fresh runners; it is not a controlled
same-machine comparison. All values are seconds.

| Platform / repetition | Baseline total | Candidate total | Total increase | Fresh-check increase | Cache-restore increase | Other net change |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Linux 1 | 224 | 405 | 181 | 157.46 | 19 | 4.54 |
| Linux 2 | 308 | 411 | 103 | 80.20 | 15 | 7.80 |
| Darwin 1 | 558 | 636 | 78 | 46.30 | 23 | 8.70 |
| Darwin 2 | 384 | 760 | 376 | 301.10 | 59 | 15.90 |

The fresh-check boundary is `just check`. In the baseline it also includes parser
and Lean builds; the candidate still builds the source parser prerequisites but
uses its restored Lean output. Comparing candidate runtime lookup directly with
baseline `just setup` would therefore omit part of the baseline build.

## Added execution inside fresh checks

Candidate case reports identify **140 new infrastructure cases in thirteen
modules**, totaling **61.9–75.5 seconds** across the eight completed cold/warm
samples. These are tests of the new build/test infrastructure, rather than new
business requirements for Atuin. They run serially in the remaining-suite group.

| Added work | Measured time | Why it runs |
| --- | ---: | --- |
| 42 Nix source-identity cases, 112 real evaluations | 20.9–31.7s | Check additions, edits, renames, deletions and excluded generated inputs |
| 12 timeout-cleanup and failure-report cases | 28.7–29.3s | Exercise real deadlines, descendant cleanup and retained failure evidence |
| Other 86 infrastructure cases | 12.0–14.8s | Validate discovery, reporting, orchestration and new runtime/build helpers |
| Three additional full CLI verifications | 14.7–29.0s | Prepare independent baselines and a successful transitive-helper case |

The first three rows partition the 140 cases; their range endpoints come from
different samples and should not be summed as one run. The CLI row is separate.
The infrastructure module durations already include their pytest startup overhead.

[Source-identity tests](../tests/test_source_identity.py) invoke real Nix evaluation
for their mutations. The timeout and report tests deliberately use three-second
test deadlines in [cleanup tests](../tests/test_timeout_cleanup.py) and
[report tests](../tests/test_suite_failure_reports.py); repeated waits explain their
nearly constant 29-second total. This is deliberate test work, not a stalled build.

The [CLI tests](../tests/cli_test.py) make 22 public verification calls instead of
the baseline's 19. Reverse-direction and schema-drift cases now each construct a
baseline through their fixture. The transitive-drift case also performs a successful
verification that the old sequence shared with its preceding case. The measured
CLI additions above come from the exact three command receipts, not entire case
setup/call durations.

Static execution mapping also finds:

- Kernel tests: 30 to 33 compiler calls and 18 to 19 checker calls. The partial-proof
  attack and independent fixtures add work; removed restoration work offsets some.
- Atuin: thirteen verifier calls before and after. Private fixture copies increase
  from one to thirteen, but measured total fixture setup is only 0.03–0.20 seconds.
- Compilation tests: thirteen compile attempts before and after, with two reaching
  the real compiler. The new fixtures do not introduce hidden compilation.
- Early-baseline tests: seven verifier calls before and after.

Across all thirty pytest launches, suite wall time minus recorded case phases is
only **8.8–10.8 seconds**. This bounds startup, collection and reporting outside
case phases; it does not establish an exact causal pytest-versus-legacy overhead.
It is already included in suite wall times and must not be added again.

## Fresh-check accounting and limits

Subtracting the measured new infrastructure and extra CLI calls gives this bridge.
The final column is an arithmetic remainder, **not an identified cause**.
Differences are calculated before rounding displayed values.

| Sample | Baseline | Candidate | Increase | New infrastructure | Extra CLI calls | Remaining difference |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Linux 1 cold | 277.2 | 353.0 | 75.8 | 66.4 | 17.5 | −8.1 |
| Linux 1 warm | 185.9 | 343.4 | 157.5 | 65.0 | 16.6 | 75.8 |
| Linux 2 cold | 280.8 | 325.7 | 44.9 | 61.9 | 14.7 | −31.7 |
| Linux 2 warm | 269.4 | 349.6 | 80.2 | 66.8 | 16.8 | −3.4 |
| Darwin 1 cold | 490.5 | 596.4 | 106.0 | 75.5 | 29.0 | 1.5 |
| Darwin 1 warm | 442.9 | 489.2 | 46.3 | 68.7 | 21.5 | −43.9 |
| Darwin 2 cold | 547.0 | 513.7 | −33.3 | 70.6 | 27.0 | −130.9 |
| Darwin 2 warm | 284.3 | 585.4 | 301.1 | 66.3 | 28.3 | 206.5 |

For example, Linux warm repetition two adds 66.8 seconds of infrastructure tests
and 16.8 seconds of CLI verifications. Other fresh work nets −3.4 seconds, leaving
the observed 80.2-second fresh-check increase. Another 15 seconds restoring the
cache and 7.8 seconds elsewhere explain its 103-second end-to-end increase.

Other rows have much larger remainders. They include avoided Lean builds, changed
kernel work, uninstrumented legacy Atuin/model/build phases and host/runtime
variation. The unchanged Darwin baseline alone ranges from 284 to 547 seconds
across these cold/warm fresh checks. Legacy logs have no separate Atuin/model case
timings. The evidence does not justify assigning the whole remainder to pytest,
fixture independence or runner noise. A same-host paired timing of an equivalent
positive verifier invocation against both prepared runtimes would isolate a
possible runtime difference without repeating the entire benchmark.

## Nix overhead despite a working cache

Candidate seeds are approximately 1.73 GB on Linux and 1.78 GB on Darwin, versus
0.31 GB and 0.415 GB for the baseline dependency-only seeds. The warm transfer
increases in the first table are measured action times, not size-based estimates.

All four candidate warm runtime lookups take **17.65–20.25 seconds** and log an
unpack of the pinned nixpkgs revision into the Git cache, even though no project
derivation rebuilds. The subsequent unit-output lookup takes only 0.69–1.05 seconds.
The baseline instead downloads/installs Lean through Elan in its roughly 10–15-second setup
phase. Warm shell-entry residuals are only about 0.6–3.4 seconds, so repeated
environment entry is not the dominant regression in these jobs.

Cold candidate runtime-plus-unit phases take 73.2–120.2 seconds before fresh
checks; baseline setup takes 10.9–17.0 seconds and its Lean build remains inside
fresh checks. Cold cache saving also adds 2–16 seconds over baseline. These are
distinct measured phase boundaries, not a claim that the entire graph-build time
is additional work; the fresh-check comparison includes the avoided checkout build.

The pinned [cache action defaults to `/nix`](https://github.com/nix-community/cache-nix-action/blob/7df957e333c1e5da7721f60227dbba6d06080569/action.yml#L55-L61);
the workflow adds no fetcher-cache path. Nix's Git fetcher cache is outside that
tree. In CI's Nix 2.35.2, the [existing-store shortcut requires a final input](https://github.com/NixOS/nix/blob/2.35.2/src/libfetchers/fetchers.cc#L278-L321),
while public [fetchTree uses a non-final input](https://github.com/NixOS/nix/blob/2.35.2/src/libexpr/primops/fetchTree.cc#L287-L304).
Its [GitHub fetch path](https://github.com/NixOS/nix/blob/2.35.2/src/libfetchers/github.cc#L245-L321)
can therefore download/unpack into the missing Git cache despite restored store
contents. This source-level explanation matches the actual warm logs. The logs do
not separate download, unpack and evaluation durations within the 18–20 seconds.

An isolated local Nix 2.18.1 probe found that preserving `lastModified` avoids a
fetch in that older version. That is **not a demonstrated fix for CI 2.35.2**, whose
shortcut differs. A narrow follow-up should compare the unchanged expression on
CI 2.35.2 with an empty versus seeded fetcher cache, identical restored store,
network blocked and no builds. No such follow-up or production change is claimed.

## Evidence and decision

Baseline: `7a99c71f40c66077b2293e1ce2c8ef3151ce5d67`; candidate:
`2aacaa4dc218b8b698bfe4bee7b00c08bd38a9a2`. The baseline has the same executable
source as the ADR's examined revision; their difference contains only documentation.
Raw per-sample artifacts in the linked run retain `evidence/sample.json`,
`work/build/ci-phases.json`, command receipts, suite JSON/JUnit and original logs.
The final collector will retain all job timings and cache post hooks together.

The owner requested this analysis before deciding on optimization or accepting
experimental-only caching. The full benchmark continues unchanged; no test was
removed, deadline shortened, verdict cached or rollout enabled for this report.
