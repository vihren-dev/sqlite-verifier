# Development replay headroom status

Status: IN PROGRESS. Created 2026-10-06.

Task: [development replay headroom](20261006-development-replay-headroom.task.md).
Source: [issue #33](https://github.com/vihren-dev/sqlite-verifier/issues/33).

## Progress

- 2026-10-06: Created workspace `replay-headroom` from reviewed T04b tip
  `06442f62`. The old storage workspace and its pending review journal
  remain unchanged. Read the issue, which has no comments, the approved
  task outcome, storage evidence, tier, loading and native-model boundary.
- 2026-10-06: Policy version 1 selects all 69 authored v5 cases, all two
  synthetic cases, one case per nonempty upstream source, and eight
  additional identities. Loading verifies every case and all acquisition
  and fidelity evidence before selection. No selected SQL or frozen bytes
  have changed. Requested an idle local host slot for fresh profiling.
- 2026-10-06: The current phase guard is 120 seconds, while historical
  receipts and documentation describe 60 seconds. The speed target is
  separately less than 30 seconds. No deadline has been raised.
- 2026-10-06: Reported the deadline discrepancy to the coordinator, who
  requested owner feedback. Changes to the guard remain pending. The
  coordinator authorized read-only profiling with the guard unchanged.
- 2026-10-06: One bounded diagnostic ran on the idle local host using the
  retained pinned Python 3.12.8 and conformance runtime, with explicit
  ordinary-file storage. It passed all 184 native comparisons and reported
  184 `MODEL_UNSUPPORTED`. The instrumented phase took 72.44 seconds:
  generic loading 65.84, synthetic loading 0.03, native replay 4.22, model
  classification 1.61, runtime binding 0.10, and selection 0.06. These are
  profiler timings, not acceptance measurements. Its 120-second process
  bound was unchanged. Local artifacts are in `build/headroom-profile/`.
- 2026-10-06: Profiling attributes 49.96 cumulative seconds to independent
  snapshot `deepcopy` operations in `native_storage.expanded_record`, with
  about 218 million total function calls. Loading's JSON decoding took
  6.01 seconds and canonical serialization 5.73 seconds. The existing
  validated snapshot bytes can support independent JSON reconstruction
  through the standard library. Requested coordinator feedback before
  this isolated change while the deadline question remains pending.
- 2026-10-06: The diagnostic process is terminal with exit code 0. Released
  the reserved local host slot to the Tcl task. No code or frozen evidence
  changed during profiling.

- 2026-10-06: The owner confirmed the 120-second phase limit in commit
  `06a1e29795de6580a14fcfceb1eddaed232177d9` and ADR 0005. The earlier
  discrepancy/feedback entries above are historical; no deadline decision
  remains pending. The separate target remains less than 30 seconds on both
  platforms. Corrected both stale current-deadline claims in
  `docs/conformance-progress.md`, preserving the historical measured bounds.
- 2026-10-06: Each snapshot now serializes once for digest validation; each
  occurrence uses standard-library JSON reconstruction from those same bytes.
  Every pool digest, reference shape, missing-reference and unused-pool check
  remains active. New nested-mutation checks preserve independent schema,
  column, row and typed-cell byte structures, including NUL/non-ASCII text,
  BLOB bytes, integer bounds, REAL signed-zero bits and NULL. All 21 focused
  transport/native-storage regressions pass in 0.30 seconds (60-second suite
  bound), including fresh native round trips for acquisition versions 1–4.
  Frozen v1–v5 have no working diff. No measurement or speed claim is made.
- Heavy benchmark validation remains held until the coordinator releases an
  idle host after PR48 full-model runs. Reviewed PR43/44/47 were not changed.

## Validation

Complete: 21 focused snapshot/storage regressions and unchanged frozen paths.
Complete: checkpoint `912b3a0e99cc0bb40977e7963e7feb9fa57facb7` passed
independent review `20261006T182926Z-912b3a0e` with no findings. The reviewer
checked both expansion callers and the approved owner deadline decision.
Complete: one fresh phase on each platform with matching historical selected
identities, profiles and verdicts. macOS took 23.699742582997715 seconds;
Linux took 49.70655691897264 seconds. Linux misses the less-than-30-second
acceptance target. The macOS phase is qualified by the ancillary retention
defect below. The approved process bound remains 120 seconds.
Pending: relevant integrated checks and Linux performance acceptance.
This task is not DONE. No further optimization or rerun is authorized in this
turn; PR48 final validation and owner review take priority.

- 2026-10-06: Recorded the no-findings implementation review and preserved its
  exact raw journal line in this status checkpoint. Benchmark remains held
  pending the coordinator's idle-host release after PR48 full-model work.
- 2026-10-06: The coordinator released each idle host for one fresh phase on
  reviewed source `82f2d178`. macOS session 35032 completed the original phase
  in 23.699742582997715 seconds, with all 184 identities and verdicts matched.
  Its report was written before ancillary summary serialization failed on
  `PosixPath` entries (command exit 1). Outer timestamps, individual fixture
  paths and in-process before/after manifests were lost. The retained
  after-only hashes and recovery summary do not reconstruct those fields.
- 2026-10-06: Linux session 49695 completed with exit 0 using the exact public
  commit archive, own pinned Nix conformance runtime and ordinary ext4 files.
  Its phase took 49.70655691897264 seconds (outer call 50.392677217), missing
  the target. All 184 fixture paths, source/runtime/corpus/Python hashes and
  outer timestamps are retained. All 835 regular source checks and the
  `CLAUDE.md` symlink passed before/after. Both host slots were released.
- 2026-10-06: Retained both raw reports, exact helpers, logs, hash manifests
  and the earlier instrumented diagnostic in
  [the dated measurement record](../reports/20261006-development-replay-headroom/README.md).
  Bounded receipt validation passed without replay or builds. An independent
  read-only audit confirmed both policies, full denominator 4378, selected
  denominator 184 and every historical identity/profile/verdict field.
  Frozen v1–v5 bytes are unchanged. This commit preserves the pending raw
  `82f2d178` independent-review journal line. No speed acceptance is claimed
  for Linux, and the task remains IN PROGRESS.
