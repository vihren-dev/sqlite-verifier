# CI performance measurements

Measured on 2026-09-25–28. Full package jobs include fresh source proof checks,
coverage evidence, native archives, offline installation, every installed-runtime
case and artifact upload. No verification result is reused from a dependency cache.

| Run | Revision / cache state | macOS | Linux |
| --- | --- | --- | --- |
| [Original successful package](https://github.com/vihren-dev/sqlite-verifier/actions/runs/36138251243) | e8502876, no cache | 23m28s | 18m33s |
| [First optimization experiment](https://github.com/vihren-dev/sqlite-verifier/actions/runs/36143187396) | 0cef4339, cold cache, xz export | Failed | 11m46s |
| [Sequential macOS experiment](https://github.com/vihren-dev/sqlite-verifier/actions/runs/36144746026) | 54ea013a, macOS cold / Linux warm, zstd export | Failed | 12m31s |

The failed macOS experiment is not a speedup or acceptance result: overlapping
kernel and CLI suites caused a valid CLI proof to exceed its production deadline.
The current implementation runs those suites sequentially on macOS and with two
workers on Linux. Linux's successful experimental pair took 160.16s, with every
case retained. Production checker deadlines remain unchanged; adversarial checker
processes in the test harness have 60s instead of 30s of bounded headroom.

Sequential macOS source checks passed, but the installed positive case still
exceeded its 30-second checker limit. Native profiling identified repeated Lean
library imports and structural comparisons as the dominant cost. The gate now
reuses import state within one invocation, retaining every declaration comparison,
replay, audit and kernel check. A fixed local sandboxed positive fixture took
10.656s with the original warm checker versus 2.599s and 2.475s with reuse.
Both diagnostic binaries used the same native optimization and source-compiled
fixture; the first original run took 17.582s with colder filesystem state.
These are checker measurements, not complete CI times. Production limits remain
unchanged. Both-platform full-package validation of this change is pending.

Protected baseline changes reject before compilation using the exact snapshotted
transitive closure. Matching inputs still compile and undergo independent kernel
verification. The new regression checks this ordering and mutates original files
after comparison to ensure they cannot change compiler inputs.

The Nix cache key contains platform and environment-file hashes. Successful main
jobs save; other jobs restore only. No `.lake`, checkout, Lean proof or acceptance
artifacts are cached. The initial Linux cache is 309,793,256 bytes. Cache restoration
and saving are included in the job measurements above.

A controlled local archive experiment changed only Nix export compression:

| Phase | xz | zstd |
| --- | --- | --- |
| Payload copying | 19.22s | 21.07s |
| Nix export | 274.73s | 9.80s |
| Signature/content verification | 3.97s | 0.69s |
| Outer gzip archive | 24.53s | 28.30s |

The zstd archive was 1,127,206,947 bytes, below the 2 GB guard; offline installation
and every installed ordinary/Atuin case passed. Nix reads the encoding from cache
metadata; no installer or signature policy changed. See the
[Nix binary-cache settings](https://nix.dev/manual/nix/2.29/store/types/local-binary-cache-store.html). These local phase measurements
are distinct from hosted end-to-end results. Single samples vary with runner load;
repeated full-package checks of the final revision are required before completion.
