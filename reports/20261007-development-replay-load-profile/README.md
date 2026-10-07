# Frozen v5 load-only cProfile diagnostic

This is **instrumented load-only** evidence. It is not acceptance or a timing
comparison. Linux's fresh 39.57022682100069-second miss remains unchanged, and
the task remains **IN PROGRESS**.

The coordinator authorized one `conformance.corpus.load` call on reviewed
source `5d15607fdf78d0a209b539ca158939739b54d377`, using the existing pinned
Linux Python 3.14.7 and all frozen v5 bindings. Session 98256 finished with
exit 0. It loaded all 4,376 generic records once. No native replay, development
selection, model execution, runtime build or source optimization ran.

The instrumented interval was 24.757685188 seconds. Parent user CPU was
23.852586 seconds, and system CPU was 0.835809 seconds. Original pstats reports
24.64460195200001 total self seconds. Profiler instrumentation adds overhead;
these numbers are separate from the earlier fresh phase and stage diagnostic.

| Function or caller | Calls | Self seconds | Cumulative seconds |
|---|---:|---:|---:|
| `expanded_record` | 4376 | 5.270413991 | 10.542457637 |
| JSON `loads`, all callers | 12212 | 0.022923934 | 6.928518427 |
| Stored-record JSON decode, from `payload_records` | 4376 | 0.007266475 | 5.265636404 |
| Canonical pool JSON decode, from `expanded_record` | 7833 | 0.015643022 | 1.074232140 |
| Canonical `serialized`, all callers | 67689 | 0.061286642 | 4.589246044 |
| Canonical `serialized`, from `expanded_record` | 37089 | 0.036862943 | 2.292366976 |
| Canonical stored-record serialization | 4376 | 0.004907782 | 2.027926385 |
| `marshal.loads` | 24880 | 1.482483149 | 1.482483149 |
| `marshal.dumps` | 7833 | 0.267605387 | 0.267605387 |
| Fidelity evidence verification | 1 | 0.002366206 | 5.087972811 |
| Acquisition verification | 1 | 0.511930717 | 3.130879275 |

Caller rows are independently extracted from the original pstats. Cumulative
rows overlap and must not be added. The 5.270414 snapshot-expansion self
seconds are not attributed to a line, allocation, garbage collection or other
operation by this profile. No predicted savings or under-30-second result
follows from the table.

## Provenance and retention

The actual private root is
`/var/tmp/sqlite-verifier-t04c-load-20261007.xkc2n62q`. UTC boundaries were
`2026-10-07T08:48:08.011588+00:00` and
`2026-10-07T08:48:32.769268+00:00`; monotonic nanoseconds were
`422533611873727` and `422558369558915`. PID and process group were 377716.
The existing `run_command` harness applied the unchanged 120-second group
bound. The two-mode observer has a main guard and is named
`t04c_load_profile.py`, so it cannot shadow Python's `profile` module.

All source, frozen v5, archive, Python and helper identities match before and
after. Full source/Python/archive identities also match the
[fresh Linux receipt](../20261007-development-replay-headroom-acceptance/README.md).
The separate frozen-v5 tree has all 122 files checked against that source
manifest. The loaded manifest, actual case names/part counts, native versions,
complete observed and declared execution profiles, canonical profile digest
and corpus binding identity are retained. The case payload digest is
`663e38016b574c8436c2bb0d53ff9e356fde51b458c1640a4a99553f11fe98b4`.
This unit invokes no runtime oracle and makes no new native-verdict claim.

The original full pstats, self/cumulative listings and complete caller views,
original command streams and capture log, UTC/monotonic markers, before/after
identities/conditions, binding observations, public helpers and preflights are
retained as 24 gzip artifacts. Compressed and original hashes are in
`raw-sha256.json`. All 16 retrieved original artifact digests match the
independent remote inventory. `callers-derived.json.gz` was computed locally
from the original pstats without another load.

One preflight helper transfer used the wrong temporary-directory name and
failed with exit 255 before any load. Its original error and the explicit
missing-original-timestamp limit are preserved. The corrected transfer and
input/helper preflight passed. No load was rerun. Full identity reads occur
outside load timing. The records identify ext4 `/dev/md127` with `rw,noatime`
and retain full host/load/memory/capacity observations. File caches were not
flushed, and residency was not observed.

Run the bounded read-only check:

```sh
nix develop path:./nix --command timeout 15 python3 -B \
  reports/20261007-development-replay-load-profile/validate.py
```

It verifies original artifact hashes, unchanged inputs, all 4,376 case/profile
bindings, one profiled `corpus.load` invocation, absence of native/model replay
functions, and every retained derived caller counter. The check passes.

## Conditional next snapshot unit

The smallest candidate is a canonical reference-size fast path for an ordinary
`dict` reference, ordinary sole `snapshot` key, and ordinary ASCII alphanumeric
`str` digest after the existing shape, digest and membership checks. The exact
size is the canonical empty-reference size plus digest length: 79 bytes for a
SHA-256 hex digest. Bounded expansion could avoid serializing that small object
for every occurrence. Subclasses and values outside that exact proof retain
the existing serializer path, including escaped or multibyte strings;
the default unbounded primitive and all malformed, missing and unused-pool
checks retain their behavior. Independent exact-size and subclass tests would
be required before such a change.

The source at `native_storage.py:94`, `:100` and `:114` and recorded counts
identify 7,833 pool, 4,376 skeleton and 24,880 reference-size serializations
within 37,089 expander serializations. The pstats caller is the function at
`:69`. Reference time is not separated from pool
and skeleton serialization; the whole caller cost is 2.292367 profiled
seconds. That is not an expected saving. A shared normalization cache would
add lifetime and memory policy, while its directly measured decode/encode
cost is 1.341838 seconds before any unknown duplicate ratio. This evidence
does not justify a cache framework or an estimate that a snapshot change
alone will meet acceptance. The coordinator selects the next authorized unit.
