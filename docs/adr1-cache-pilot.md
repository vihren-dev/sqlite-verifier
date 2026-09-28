# ADR 0001 cache pilot: 2026-09-28

[Run 36410934815](https://github.com/vihren-dev/sqlite-verifier/actions/runs/36410934815)
used candidate revision `2bd6f604744f9a3cf58d784a51b5ba1150282142` on four fresh
native runners. This verifies cache transport and evidence collection. It is one
repetition without a baseline comparison and does not authorize performance rollout.

| Platform | Cold total | Warm total | Warm restore | Cold save | Compressed cache bytes |
| --- | --- | --- | --- | --- | --- |
| x86_64-linux | 8m46s | 5m11s | 36s | 20s | 1,731,976,808 |
| aarch64-darwin | 10m41s | 11m39s | 76s | 51s | 1,780,962,687 |

Totals include checkout, Nix installation, cache work, builds, fresh checks,
artifact upload and post hooks. Restore/save values are GitHub step durations.
The byte counts match both completed-transfer logs and the cache API entries.

Both cold jobs saved their exact isolated main-ref keys. Both warm jobs reported
`CACHE_HIT=true`, restored exactly their matching cold key, and reused the same
runtime and pure-unit store paths. No project derivation was rebuilt on warm runs;
installer user-environment builds occurred before cache restoration.

Every sample has 352 passing fresh source cases plus 64 disjoint unit cases,
covering exactly the 416-source-case catalogue. All setup/call/teardown phases
pass, source receipts match their fresh coverage UUIDs, and disk post-hook markers
appear after cache saving. Installed acceptance was checked separately in native
CI; pilot samples intentionally use the complete source-check scenario only.

Darwin's warm total was slower despite correct reuse. Runtime lookup fell from
65.56s to 19.39s and unit lookup from 3.35s to 0.97s, while fresh checks increased
from 393.43s to 556.19s. These single observations cannot establish a performance
improvement or regression against the optimized baseline. Three repetitions per
platform/scenario remain required by the [benchmark protocol](adr1-benchmarks.md).

## Resource observations

| Platform / scenario | Sampled filesystem peak used bytes | Minimum available bytes |
| --- | --- | --- |
| Linux cold | 71,676,825,600 | 84,204,007,424 |
| Linux warm | 70,375,747,584 | 85,505,085,440 |
| Darwin cold | 310,247,645,184 | 32,825,450,496 |
| Darwin warm | 309,499,555,840 | 33,573,539,840 |

These are whole-filesystem observations, including pre-existing runner-image
contents, not project allocation. Workspace, temporary files and Nix share the
same filesystem in these samples; their identical measurements are not summed.

The repository's read-only cache storage-limit API returned `max_cache_size_gb: 10`.
Six candidate seeds alone would total 10,538,818,485 bytes, before baseline seeds.
The complete benchmark therefore groups the unchanged sixty samples by repetition:
four cold seeds followed by sixteen restored jobs, then the next repetition.
A fixed non-cancelling workflow concurrency group prevents overlapping experiments.
No cache deletion, storage-limit increase or billing change was made.

## Corrections and retained evidence

The pilot's collector originally recognized download `Cache Size` records but
missed upload `Sent ... of ...` records. The corrected collector accepts completed
Sent/Received totals and deduplicates progress repeats. Its existing fifteen
cases pass together, alone and reversed; reprocessing the pilot's raw logs yields
the byte counts above. All raw logs and original reports remain intact.

The downloaded `adr1-benchmark-summary` artifact contains job metadata, raw logs
and original `summary.json`. Local review additionally retains
`build/adr1-pilot-summary/summary-with-transfer-totals.json`. Its only readiness
error is the expected `Expected exactly 60 unique native samples`; every pilot
cache, disk, selection and correctness check passes. `rollout_enabled` remains
false. Normal CI continues to use dependency caching while full measurements run.

Separately, normal source-mode CI exposed one loader-test import dependency.
The follow-up scopes the packaging search path and forces a fresh sibling import;
all nineteen affected cases pass independently and reversed, preserving every
original assertion. This test-only correction does not change the runtime outputs
whose reuse was measured here. Final source-mode native revalidation is pending
in PR 5 before the full benchmark is dispatched.
