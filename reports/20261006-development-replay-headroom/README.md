# Development replay headroom measurements

T04c remains IN PROGRESS. One fresh phase on macOS took
**23.699742582997715 seconds**. One fresh phase on Linux took
**49.70655691897264 seconds**. Linux misses the separate less-than-30-second
acceptance target. Both phases used the owner-approved 120-second process
bound and preserved all 184 selected identities and verdicts.

The source was reviewed commit `82f2d1786cd732b4b89f813680506ca631239887`,
including snapshot reconstruction from `912b3a0e99cc0bb40977e7963e7feb9fa57facb7`.
The code, native comparator and model classification were unchanged during
measurement. Each driver called the original development report once with
an explicit ordinary-file fixture directory. No success cache or profiler
was used in these two phases. The bound remains 120 seconds; the acceptance
target remains less than 30 seconds on each platform.

## Retained observations

| Platform | Fresh phase seconds | Phase below 30 seconds | Receipt limitation |
| --- | ---: | --- | --- |
| macOS 26.2 arm64 | 23.699742582997715 | Yes | Ancillary summary serialization failed after the phase report was written. |
| Linux 7.1.5 x86_64 | 49.70655691897264 | No | Complete phase, outer timestamps, fixture paths and before/after identities retained. |

All 184 outcomes are `MODEL_UNSUPPORTED`, as in the historical receipts.
These phases check native replay and unchanged unsupported classifications;
they do not demonstrate successful Lean model comparisons for these cases.
For both generic and synthetic inputs, corpus and manifest digests,
execution profiles, denominators, selected names and identity digests,
case verdicts and counts match the corresponding retained
`20261002-adr5-review-v5-sample-{darwin,linux}.json` receipt. These comparisons
establish unchanged observations. Historical timings and the earlier
instrumented diagnostic are separate runs, not paired speed measurements.

### macOS retention defect

`darwin/report.json.gz` is the complete report written by the original
driver. The driver then failed while serializing `PosixPath` fixture entries
in the ancillary summary; `darwin/run.log.gz` retains that traceback. The
phase and its identity, verdict, 184-fixture and cleanup assertions had
completed. The outer monotonic start/end timestamps, individual fixture
paths and in-process before/after hash manifests were **not retained**.
They are not reconstructed here. The command exited 1 after the phase.
The ancillary load average was also lost. The macOS driver did not collect
a Python executable hash; only the actual pinned invocation path is known.

`darwin/summary-recovered.json.gz` contains the actual report, comparison
checks repeated against the retained historical receipt, actual storage
device and cleanup observation, and **after-only** file hashes. It states
the missing fields explicitly. Its hashes must not be treated as retained
before/after manifests. The observed ordinary-file directory was
`/Users/tzankomatev/work/sqlite-verifier-headroom/build/headroom-acceptance-darwin/native-storage`.
The Python 3.12.8 invocation and compiled runtime path are in `receipt.json`;
the native library, parser and model digests are in the after-only manifest.

A preflight invocation failed at import because `PYTHONPATH` omitted the
checkout. It ran no report or native fixture phase. The measured invocation
set `PYTHONPATH` to the checkout. No completed phase was rerun.

### Linux retention

The public commit archive and exact helper were transferred into a fresh
`/var/tmp/sqlite-verifier-headroom.j1WL5z` directory on `vihren`. The transfer
hashes passed before extraction. The archive SHA-256 is
`8a81b8598d2f194ef5b73d51fc5b2857b8e1155b43c54a59411178cbbc260957`.
The archive command, byte size and all 835 regular source-file hashes are
retained. Every source hash and the `CLAUDE.md -> AGENTS.md` symlink passed
before and after the run. The archive itself remains in the ignored build
directory; it is reproducible from the exact public commit.

The source's own pinned Nix environment selected Python 3.14.7 and built its
own conformance runtime. `linux/headroom-runtime-build.log.gz` retains the
successful runtime result. The source Lean pin is 4.33.0; no separate Lean
binary version result is claimed. Runtime paths and executable digests are
retained rather than inferred from another task's runtime.

The selected directory was
`/var/tmp/sqlite-verifier-headroom.j1WL5z/source/build/headroom-acceptance-linux/native-storage`,
on the ordinary `/dev/md127` ext4 mount with `rw,noatime`. All 184 actual
`case.db` paths and cleanup results are in `linux/summary.json.gz`. Exact
before/after code, frozen corpus, Python, native library, parser and model
hashes match. The outer call took 50.392677217 seconds; the authoritative
development phase report measured 49.70655691897264 seconds. The command
exited 0, and its explicit `underTarget` result is false.

## Evidence and checks

Raw files are gzip-compressed without changing their uncompressed bytes.
`raw-sha256.json` binds each compressed file, original bytes and size.
`receipt.json` records provenance, actual process handles, storage and
retention limits. `diagnostic/` preserves the earlier cProfile diagnostic
and its original helper, report, text profile and raw profiler data; those
instrumented timings are not acceptance measurements. The archived helpers
are the exact executed versions, including the macOS serialization defect.

From this directory, `python3 validate.py` checks retained hashes, historical
identity/verdict comparisons, Linux source checks, exact timestamps and
fixture-path counts, and the macOS missing-field qualification. It does not
run replay or build a runtime. The receipt checks passed. Frozen v1–v5 had
no diff from the reviewed source. Integrated ordinary and Nix checks remain
pending. Both host slots were released; no further optimization or
measurement is authorized in this turn.
