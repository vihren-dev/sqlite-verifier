# Linux replay diagnostic

T04c remains IN PROGRESS. This is one **instrumented diagnostic**, not a new
acceptance measurement. It identifies both CPU loading and native file
replay as substantial costs. No production code changed. The previous fresh
Linux phase remains 49.70655691897264 seconds and misses the separate
less-than-30-second target.

The coordinator authorized one diagnostic with the unchanged 120-second
bound, reviewed source `82f2d178`, the same pinned conformance runtime,
full validation, all 184 selected identities and ordinary ext4 files.
Session 60672 completed with exit 0. Its original report measured
53.62880020798184 seconds; the outer instrumented call took 54.308965406
seconds. The Linux heavy slot was released immediately after completion.

## Observed costs

| Stage | Instrumented wall seconds | Parent user + system CPU seconds |
| --- | ---: | ---: |
| Full generic loading and validation | 27.892518 | 27.819581 |
| Synthetic loading and binding | 0.008855 | 0.008865 |
| Native replay of all 184 cases | 24.968640 | 5.561513 |
| Current-model classification | 0.367574 | 0.288213 |
| Runtime executable binding | 0.284923 | 0.284340 |
| Selection | 0.098798 | 0.098366 |
| Result binding | 0.001080 | 0.001232 |

Classification also used 0.093584 seconds of child CPU. All outcomes remain
`MODEL_UNSUPPORTED`; this is native replay plus unsupported classification,
not successful Lean model comparison. Writing the final report outside the
measured phase took 0.000749329 seconds.

Loading is almost entirely CPU work. cProfile attributes 13.992 cumulative
seconds to JSON decoding: 7.971 from repeated independent snapshot
reconstruction and 5.411 from stored-case parsing. Canonical serialization
took 7.537 cumulative seconds: 6.157 from the combined stored/expanded case
size checks and 1.057 from pooled snapshot digest validation. The same
`payload_records` caller performs both size checks, so this profile does
not separate those two serialization costs.

Native replay's wall time exceeded its parent CPU time by 19.407127 seconds.
It wrote 64,288 output blocks and 32,915,456 process I/O bytes on ordinary
`/dev/md127` ext4 with `rw,noatime`. The native statement executor accounts
for 21.154 cumulative seconds, including 20.624 seconds in its own body.
This supports an I/O-wait hypothesis. The probes do **not** observe `fsync`
calls directly, so they cannot assign that entire gap to `fsync`. Small
negative wall-minus-CPU differences in short stages are retained as observed;
the clocks and resource probes have distinct measurement boundaries.

The smallest identified CPU candidate is exact compositional expanded-case
byte-size accounting from already validated snapshot JSON. It could remove
one whole expanded-record serialization while preserving every stored and
expanded size limit, digest/reference/missing/unused-pool check, and fresh
independent occurrence. Before production use, its computed length must
equal canonical serialization at exact size boundaries, including NUL,
non-ASCII bytes and corrupted/unselected evidence. The measured combined
6.157 seconds is an upper bound on the relevant cost, not expected savings.
This candidate alone does not establish the target while native replay
takes about 25 seconds. No candidate was implemented during this diagnostic.

## Retention and scope

`diagnostic/` retains the exact executed helper, driver, profiler data,
cumulative/internal profiles, stage observations, complete original report,
before/after identities, actual fixture paths and source/storage checks.
`profile-callers.txt.gz` is a derived local view of the retained profiler
data, generated after the process completed. All 835 source checks and the
`CLAUDE.md -> AGENTS.md` symlink passed before/after. The 265 observed code,
corpus, Python, native-library and runtime hashes match before/after.
Every selected identity, profile, count and verdict matches the previous
Linux receipt; all 184 actual fixture paths are distinct, ordinary
`case.db` files and were cleaned. Full denominator 4378 and frozen bytes
are unchanged. Hashing reads source/corpus/runtime files before profiling;
these are fresh application calls, not claims of a cold OS file cache.

`preflight/` preserves the earlier helper setup failure. Naming the remote
helper `profile.py` shadowed Python's standard `profile` module during
`cProfile` import. It failed before `replay_tiers.report` or any SQLite
fixture execution. An empty storage directory and identity manifest were
created during that import. The coordinator confirmed that the one actual
diagnostic had not run and retained the lease. The corrected setup used the
same helper bytes under `t04c_diagnostic.py` in a separate fresh directory.
No completed diagnostic was rerun.

`raw-sha256.json` binds all 27 raw compressed files and their exact original
bytes. `receipt.json` records provenance, process handles, costs and limits.
`python3 validate.py` checks retained evidence without replaying or building.
The bounded checks passed. All 22 earlier raw measurement/diagnostic artifacts
and the append-only review journal remain preserved. Integrated ordinary/Nix
checks and Linux performance acceptance remain pending.
