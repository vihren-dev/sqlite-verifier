# Exact Tcl values: native full acceptance

The reviewed T17 assembly passes the configured full model gate on native
Darwin and Linux. Both runs use public source
`970e89ff1e6999bed12afe1d28d3d703d218b5ac`, the same ordered 32 model modules,
the reviewed 600-second model deadline and a 900-second outer bound. The other
six target deadlines remain 420 seconds.

| Native platform | Full model | Pytest seconds | Outer monotonic seconds | Upstream Tcl suite |
|---|---|---:|---:|---|
| aarch64-darwin | 323 passed, 1 existing skip | 578.425 | 581.378 | 117 passed, no skips; unchanged cached receipt |
| x86_64-linux | 323 passed, 1 existing skip | 347.663 | 349.456 | 117 passed, no skips; fresh 20.085-second run |

The model's existing Tcl-source test says to run the pinned upstream target.
That target includes the direct precision, binding, policy and native replay
tests and passes without skips on both platforms. Darwin reused the exact
upstream derivation/JUnit from the checked assembly, whose original run took
5.016 seconds; it did not rerun that suite. Neither full model run was cached.

Darwin's model wall timestamps span overnight, from 2026-10-06 19:32:12 UTC to
2026-10-07 06:30:12 UTC. Its shorter monotonic and pytest durations are retained
separately. These are correctness receipts, not comparable performance
measurements or evidence of platform speed parity.

Linux's first helper stopped before any suite because read-only Nix evaluation
reported an unrealized source path. The separately hashed Linux helper adds
`--read-write-mode` to that evaluation only. The failed preflight helper/log,
both exact executed helper texts and their hashes remain in the receipts.
After both remote gates and source verification completed, the overnight SSH
client ended with a connection reset; the remote process records and raw JUnit
establish the gate results.

Each platform verified all 902 archived public regular files and the authored
`CLAUDE.md -> AGENTS.md` symlink before and after execution. Every realized Nix
input is bound to that same archive: 328 model files and 182 upstream files.
The receipt retains actual source, derivation, runtime and output paths, full
rendered commands, ordered test modules, deadlines and exact raw JUnit.

[summary.json](summary.json) records the results and invocation identities.
[raw-receipts.json.gz](raw-receipts.json.gz) contains 35 original UTF-8 payloads;
[sha256.json](sha256.json) records each original byte count and SHA-256.
Every embedded payload was checked against its original bytes after retrieval,
and the compressed/raw aggregate hashes are recorded in the summary. The Linux
task directory `/var/tmp/sqlite-verifier-t17-acceptance.Cf3bM9` remains retained.

[preservation.json](preservation.json) compares this source to reviewed assembly
`496ca5b6`: all frozen v1–v5 trees, 31 retained date/codec files, nine earlier
integration receipts and suite ownership are byte-identical. All 73 prior raw
review rows remain an exact journal prefix in order. The existing first-20
date-family cohort, original SQL, binding identities and refusal denominators
are unchanged; no new acquisition ran for this acceptance.

The earlier [acquisition report](../20261006-tcl-values.md) remains an immutable
dated checkpoint. This receipt supplies its then-pending full model gate; it
does not claim production date-function support or model agreement for the
unsupported date cohort. The [task status](../../plans/20261006-exact-tcl-values.status.md)
remains IN PROGRESS pending reviewed delivery. No protected baseline, kernel
gate, release, issue closure or frozen PR43/44/47/48 changed.

For publication, the coordinator authorized only the reviewed merged timeout
tip `d8faab74`, excluding later main metadata `6852f6fa`. The equivalent timeout
comment and append-only journal were the only conflicts. Both original journal
orders remain intact: 79 T17 rows and 50 incoming rows form 81 distinct exact
rows with 40 unique reviews. Three real command/routing checks and all six CI
checks pass after integration. [publication-targets.json](publication-targets.json)
records that both platforms' complete model/upstream source, derivation, output
and rendered command identities still equal those accepted above.
[publication-checks.json](publication-checks.json) records the bounded checks
and original compressed JUnit digests. No additional runtime change was needed.
