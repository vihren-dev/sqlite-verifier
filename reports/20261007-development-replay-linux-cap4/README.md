# One fresh Linux phase on the executor integration

The one authorized uninstrumented phase is terminal: handle 42003, exit 0.
Its receipt is valid, but its **33.707907736999914-second** report phase
misses the strict under-30-second target. The outer report call took
34.524907143 seconds. The process-group guard remains 120 seconds.
No performance rerun, profile or diagnostic followed this observation.
T04 remains **IN PROGRESS**.

The phase used reviewed compiled source
`c3e8f5186e2865b5cdc0ea5af1a9d0924531752a` and exact native runtime
`/nix/store/ixl6nwa1nk8ah8138axkqkgian4a27bc-sqlite-verifier-conformance`.
Every one of the 1,113 source entries and 17,936 runtime files is bound
before and after, along with the source archive, Python, both helpers and
the used SQLite 3.51.0 library. These identities also match the retained
exact-source runtime build. The complete identities are unchanged.

Full v5/workload loading and binding checks precede selection. The full
denominator is 4378; all 184 selected identities, profiles, native evidence,
model classifications and policy fields match historical v5. All 184 native
comparisons passed. The model classified every case as `MODEL_UNSUPPORTED`;
this establishes no supported-model agreement.

The already reviewed capture driver calls the real report once, with its
unchanged storage/path arguments and group bound. Only its source-label
literal changed from the prior measured source to `c3e8f518`. Its exact
original, current bytes and one-line diff are retained. The actual source
and runtime remained unchanged during the phase. This direct report driver
retains original stdout/stderr and full JSON report bytes; pytest/JUnit was
not invoked.

Actual UTC boundaries were `2026-10-07T11:28:50.300534+00:00` through
`2026-10-07T11:29:24.825432+00:00`. Monotonic nanoseconds were
432175900820075 and 432210425727218. All 184 unique actual `case.db`
paths are retained in input order below
`/var/tmp/sqlite-verifier-t04c-executor-runtime-20261007.axs5nwGM/linux-cap4-acceptance/native-storage`.
The source checked each fixture while it existed; all paths and their
private directories were cleaned. A later remote observation also found
the selected storage empty. Storage is ordinary ext4 on `/dev/md127`,
mounted `rw,noatime`; its device number is 2431 before and after.

The resource guard passed. The preflight observed no native project
build/test/replay co-runner. A separate short host-activity check records
persistent services and nonzero background CPU; it is outside the phase.
Full host/load/filesystem observations remain intact. Identity reads occur
outside the report timing. OS caches were not flushed; residency is unknown.
This observation makes no causal speedup claim against earlier source or
runtime. The phase has no stage or CPU attribution.

`raw-sha256.json` binds all 20 raw gzip artifacts. All 13 retrieved originals
match their remote hashes and lengths. Earlier receipts and their target
misses remain unchanged. Run the bounded read-only evidence checks:

```sh
nix develop path:./nix --command timeout 15 python3 -B \
  reports/20261007-development-replay-linux-cap4/validate.py
nix develop path:./nix --command timeout 15 python3 -B \
  reports/20261007-development-replay-linux-cap4/check_mutations.py
```
