# Development replay headroom status

Status: IN PROGRESS. Created 2026-10-06.

Latest result: the complete 2026-10-07 fresh receipts on reviewed publication
source are valid on both platforms. Darwin took 21.434975332995236 seconds;
Linux took 39.57022682100069 seconds and still misses the target below
30 seconds. Evidence is retained in
[the new acceptance record](../reports/20261007-development-replay-headroom-acceptance/README.md).
The task is not DONE. No phase was rerun after the Linux miss.

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
- After the implementation checkpoint, heavy benchmark validation was held
  until the coordinator released an idle host after PR48 full-model runs.
  Reviewed PR43/44/47 were not changed.

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
This task is not DONE. The earlier measurement turn held further optimization
and reruns while PR48 final validation took priority. The coordinator later
authorized one Linux diagnostic below. No production change followed it.

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
- 2026-10-06: Receipt commit `0aca8aef80da5befbfe550a8820dc5262bf4ab7c`
  passed independent review `20261006T185111Z-0aca8aef` with zero must findings
  and one should finding. Named the validator's fixed selection count, phase
  guard and archived source count, as requested. Receipt validation passed
  again within 15 seconds; no native phase or build was run. Recorded the
  finding as fixed and preserved its raw review/resolution journal lines.
- 2026-10-06: Refactor commit `1af6f15b9ff2a6b9c22bf8f12dd5a3d9c5377b8a`
  passed independent review `20261006T185207Z-1af6f15b` with no findings.
  The two one-run receipts and qualified outcome are committed on local
  bookmark `t04c-replay-headroom`. This status checkpoint preserves the
  refactor's exact raw review line. Relevant integrated ordinary/Nix checks
  remain pending; Linux under-30-second acceptance remains unmet. No further
  optimization or measurement was run. Task status remains IN PROGRESS.
- 2026-10-06: The coordinator continued this active task with one bounded
  Linux diagnostic. Its first helper setup failed because `profile.py`
  shadowed the standard library during cProfile import, before any report or
  SQLite fixture execution. Preserved that failure, corrected the filename
  in a fresh directory, and used the retained source/runtime/storage checks.
- 2026-10-06: The one actual diagnostic, session 60672, completed with exit 0
  under the unchanged 120-second bound. Its instrumented phase was
  53.62880020798184 seconds: loading 27.8925 seconds (27.8196 parent CPU),
  native replay 24.9686 (5.5615 parent CPU), classification 0.3676. The large
  native non-CPU gap supports an I/O-wait hypothesis; fsync was not measured
  directly. Canonical size serialization was 6.157 profiled seconds combined;
  snapshot reconstruction JSON decoding was 7.971. These are diagnostic costs,
  not acceptance timings or proof that a size-accounting change meets 30.
- 2026-10-06: Retained all 27 raw setup/diagnostic artifacts in
  [the Linux diagnostic](../reports/20261006-development-replay-linux-profile/README.md).
  Both bounded receipt validators pass. All 835 source checks, 265 before/
  after identities and 184 fixture/profile/verdict comparisons match. The
  prior 22 raw artifacts, frozen bytes and final pending journal line remain
  preserved. Linux heavy slot released; no production change, full-model gate,
  additional actual phase or benchmark campaign ran. Task remains IN PROGRESS.
- 2026-10-06: Diagnostic commit `db970e10a31f0077fd8cb32e3b323dd8a7aff318`
  passed review `20261006T191103Z-db970e10` with zero must findings and three
  should findings. Named the evidence validator's unchanged fields, observer
  hash exceptions, observed filesystem and preflight markers. All three are
  recorded as fixed. Both bounded receipt validators pass; this refactor
  changes no production code, raw evidence or measured result.
- 2026-10-06: Refactor `d4c2e2445054deaf1ec7f71773279b8851180181`
  passed independent review `20261006T191308Z-d4c2e244` with no findings.
  This status checkpoint preserves its exact raw journal line. The diagnostic
  and its limits are committed on `t04c-replay-headroom`. The coordinator has
  the measured costs and the conditional exact-size candidate. No additional
  production change or native execution was started; the task is not DONE.
- 2026-10-06: The coordinator authorized the measured exact-size CPU candidate.
  `expanded_record` now accepts an optional logical byte limit. It counts
  canonical reference-skeleton bytes and each validated snapshot replacement,
  including negative deltas and every repeated occurrence. All digest,
  reference, missing and unused-pool checks still precede logical-size refusal;
  each occurrence still reconstructs an independent mutable JSON tree. The
  default primitive remains unbounded. `payload_records` keeps its stored-size
  check and requests this logical limit instead of serializing the complete
  reconstructed record again. No framework or alternate expansion path was
  added.
- 2026-10-06: All 84 focused snapshot, storage, shard and tier checks pass in
  0.87 seconds under a 60-second suite bound, with existing pinned native and
  conformance paths. Independent serialization oracles cover exact and +1
  limits, escaped/multibyte metadata, repeated/empty snapshots and nested
  mutations. Tiny limits cannot hide malformed/unused pools. A logically
  oversized unselected case with small shared storage still fails complete
  shard loading with its exact byte count. Frozen bytes, profiles, SQL,
  selection, both historical receipt sets and the 120-second guard are
  unchanged. The pending final raw diagnostic-review line is preserved.
- This is a partial CPU change. The previous diagnostic's native replay was
  about 25 seconds, with about 19.4 seconds outside parent CPU, and stored-case
  parsing was 5.411 profiled seconds. Those are prior observations, not new
  measurements of this code. This unit does not establish under-30-second
  acceptance. No new phase, native-I/O change, full-model gate or timing
  campaign ran; integrated checks and Linux performance acceptance remain
  pending. Task status is IN PROGRESS.
- 2026-10-06: Exact-size commit `16f2deecfd9cec5bc6fa86e3fce7caf138a98061`
  passed independent review `20261006T192320Z-16f2deec` with no findings. The
  reviewer confirmed canonical byte equivalence, validation order, both size
  checks, primitive flexibility and the independent oracle coverage. This
  status checkpoint preserves the exact raw review line. No new timing or
  native-I/O work followed the checked partial CPU change.
- 2026-10-07: The coordinator authorized the isolated snapshot reconstruction
  candidate. Each validated snapshot's canonical JSON is decoded once, then
  converted to an internal marshal version-2 copy. Every occurrence reconstructs
  a fresh tree from those internal bytes. Canonical JSON still determines hashes,
  exact sizes and normalization; external binary data is not an input. Digest,
  reference, missing/unused-pool checks and the unbounded default remain intact.
  Added independent JSON-oracle, scalar, nested-alias and subclass-normalization
  checks plus a deterministic once-per-pool decoding check. All 89 focused
  reconstruction, snapshot, native storage, shard and tier checks pass in
  1.64 seconds under a 60-second suite bound in the pinned Nix environment.
  The native checks use existing pinned SQLite and conformance paths. No build
  or development replay phase ran. Independent review is pending. Frozen
  evidence, native SQL/profiles, selection and the 120-second guard are
  unchanged. No performance acceptance or timing savings are claimed.
- 2026-10-07: Snapshot reconstruction commit
  `c8001b457d20c9787418a7a038cb991f185346ae` passed independent Claude review
  `20261007T064212Z-c8001b45` with no findings. This checked unit is complete.
  The raw review row is retained in the append-only journal. Native concurrency,
  integrated checks and both-platform performance acceptance remain pending;
  the overall task remains IN PROGRESS. No benchmark, SSH or PR operation ran.
- 2026-10-07: The coordinator authorized the isolated development worker unit
  from the retained native I/O-wait diagnostic. Two spawned stdlib workers
  call the unchanged serial primitive for independent cases. Ordered results
  retain all returned fixture paths and the first input failure; native errors
  preserve their code through a pickle-safe envelope. Parent-owned private
  file trees remove crash remnants after worker shutdown. The real tier CLI
  tests now use the existing process-group timeout harness at the unchanged
  120-second bound. Added actual-native equivalence, clock/TZ, failure-path,
  native-code, abrupt-crash and outer-group termination checks. Relevant Nix
  source/test ownership includes the helper. All 21 final worker, failure-order,
  tier and ownership checks pass in 7.47 seconds; all eight selected binding,
  ownership and Nix dependency checks pass in 21.22 seconds. Each suite has a
  60-second outer bound. An earlier input failure retains precedence when a
  later worker crashes. The two real
  tier CLI phase tests were updated but have not run in this unit. Independent
  review is pending. No timing phase, broader gate, build, SSH or PR ran.
- 2026-10-07: Worker commit `efcc16a43225515a713b997483c11a78fee7ab33`
  completed Claude review `20261007T073101Z-efcc16a4` with zero must findings
  and two should findings. Added real three-case CLI/report forwarding coverage
  for selected file storage and actual path auditing. The crash diagnostic now
  names the first case without a result and directs serial replay. Added
  successful-prefix diagnostic coverage. All 23 selected worker, routing,
  failure-order, tier and ownership checks pass in 7.64 seconds under a
  60-second suite bound. Both findings are fixed; refactor review is pending.
  No frozen development timing run or broader gate started.
- 2026-10-07: Refactor `96715fffc44de0ed332727ce466cc688e1ac818a` passed
  independent Claude review `20261007T073545Z-96715fff` with no findings.
  The worker unit is checked and reviewed. The earlier two should findings
  have fixed resolutions in the preserved append-only journal. This checkpoint
  records the completed unit; integrated gates and both-platform timing
  acceptance remain pending. The overall task remains IN PROGRESS. No
  benchmark, broader gate, build, SSH or PR operation ran in this unit.
- 2026-10-07: The coordinator authorized publication-base integration from
  reviewed main `bc9e2dce58f755b608cf00e545162257b81ab51a` before acceptance.
  The only merge conflict was the append-only journal. Its resolution preserves
  all 90 exact rows from both histories, including the pending worker review.
  Worker/snapshot code, frozen v1-v5 and prior T04c receipts have no diff from
  the reviewed task tip. Main's Lean 4.34.1, runtime, FK acquisition and owned
  suite routing are inherited. The development guard remains 120 seconds.
  All 53 selected routing, snapshot, worker and ownership checks pass in
  8.69 seconds under a 60-second bound with an existing Lean 4.34.1 runtime.
  This is routing evidence; exact-source runtime builds and fresh acceptance
  are still pending. Merge review is pending. T02 released Darwin after its
  terminal runtime/input checks; no acceptance phase has started.
- 2026-10-07: Merge `5d15607fdf78d0a209b539ca158939739b54d377` passed
  independent Claude review `20261007T074749Z-5d15607f` with no findings.
  Review session 71502 is terminal, exit 0. Its exact pending journal row is
  preserved with this evidence unit. The reviewed source-only public archive
  has SHA-256 `86b96911dae99a77ef8158c8ac53c548b69896744de904365545ded78bc4f422`.
  Each host checked its 933 regular source files and `CLAUDE.md` symlink.
- 2026-10-07: Source archive, Darwin metadata and Linux ambient-Python
  preflight failures invoked no phase. Retained their recorded failures and
  explicit missing-original-timestamp limits. The metadata failure retains
  its recorded message, not an original complete traceback. Corrected setup
  used the shared Git object store, resolved devices and the existing pinned
  Linux Python. The successful metadata checks preceded either phase.
- 2026-10-07: Own exact-source conformance runtime builds are terminal on
  both platforms: Darwin session 89656 and Linux session 81189, exit 0.
  They use Lean 4.34.1 and Python 3.14.7. Darwin runtime is
  `/nix/store/2w1dv3hhnrcjrcm7qp43jpdbxsgvr6wl-sqlite-verifier-conformance`;
  Linux runtime is
  `/nix/store/rhinzr7jq41azsh6s8i8dmndi7idnv3k-sqlite-verifier-conformance`.
  Full before/after identities match for all source, runtime, helper, archive,
  Python and every used native-library byte. Actual runtime manifests retain
  17,886 Darwin and 17,925 Linux regular-file hashes.
- 2026-10-07: T02 released Darwin after terminal cheap runtime/input checks.
  The coordinator reserved both heavy slots. The one fresh Darwin capture,
  session 81440, finished with exit 0: phase 21.434975332995236 seconds,
  outer call 22.19781625. The one fresh Linux capture, session 22014, finished
  with exit 0: phase 39.57022682100069 seconds, outer call 40.432509126.
  Linux still misses less than 30 seconds. The unchanged process-group guard
  is 120 seconds. Complete reports match every historical selected identity,
  profile and verdict, with full denominator 4378 and all 184 selected native
  comparisons passing. All 184 classifications are `MODEL_UNSUPPORTED`.
  No profile instrumentation, unchanged restart or timing rerun occurred.
- 2026-10-07: The public capture helper's main guard prevents spawned workers
  from restarting the observer. It calls the real report directly with
  explicit ordinary storage and actual fixture-path auditing. Both receipts
  retain UTC and monotonic boundaries, all 184 unique ordered `case.db` paths,
  private roots, cleanup, machine/load/memory/capacity and original streams.
  Linux observed ext4 `/dev/md127`, `rw,noatime`. Darwin's original GNU `df`
  described the sealed snapshot through a firmlink; an explicitly after-only
  native reconciliation identifies writable APFS Data and matches actual
  device 16777242 retained before and after. Original observations remain
  unchanged. Full identity reads occur outside phase timing; OS caches were
  not flushed and residency was not observed. No zero-load claim is made.
- 2026-10-07: Retained all 37 raw artifacts as exact gzip bytes with compressed
  and original SHA-256 manifests. Linux retrieval session 67302 is terminal;
  all 14 retrieved original artifact digests match the independent remote
  inventory, which also found cleaned storage. The new bounded validator and
  four independent identity/native-hash/fixture/target corruption checks pass
  within their 15-second bounds without replay or builds. A separate read-only
  T02 audit confirmed the complete Darwin binding, archive, fixture and
  filesystem qualifications. Frozen v1-v5, SQL/profiles, selection, previous
  receipts and the 120-second guard remain unchanged. Evidence review is
  pending. Linux performance acceptance and the overall task remain pending;
  no additional diagnostic or optimization is authorized in this unit.
- 2026-10-07: Evidence commit `34588475becd13bbfa41e9620b3cc474058b9a64`
  passed Claude review `20261007T082052Z-34588475`, session 31226 exit 0,
  with zero must findings and three should findings. Named the retained
  phase/target, denominator, model classification and Lean-version policies,
  and corrected the JSON-object narrowing docstring. A small policy module
  keeps the validator below the repository's 200-line limit. This refactor
  changes no raw artifact, measurement or outcome. All three findings have
  fixed journal resolutions. The bounded receipt and corruption checks pass
  again in the pinned environment; refactor review is pending.
- 2026-10-07: Refactor `90ed5e5b161e648cb1422d74f8b9c47a95154d11` passed
  independent Claude review `20261007T082252Z-90ed5e5b`, session 68123 exit 0,
  with no findings. The reviewer read the code; its attempted check launcher
  was not approved. The author's bounded pinned receipt and four corruption
  checks are terminal successful. The reviewed evidence unit is complete.
  Linux's target miss remains unchanged, and the overall task is IN PROGRESS.
- 2026-10-07: After the evidence review, the coordinator authorized one Linux
  diagnostic of the exact measured source `5d15607f` and existing verified
  runtime. It observes the report's seven existing top-level stage names,
  including `replay_native_cases`, with monotonic wall time and both parent
  and reaped direct-child CPU deltas. Child CPU may exceed wall time; a CPU
  difference is not an I/O or fsync measurement. The helper preserves return
  values and exceptions and has a spawn main guard. Bounded local pure-helper
  preflight passes without invoking a report. The actual diagnostic is pending;
  no production change, source rebuild or new acceptance phase is authorized.
- 2026-10-07: The single authorized Linux stage diagnostic is terminal:
  session 81515, exit 0, valid receipt. Its instrumented phase took
  39.26042659499217 seconds; outer call 40.081648631. The unchanged bound is
  120 seconds. All seven existing stage names retain original results and
  exceptions. Loading took 20.791746283 seconds with 20.736654 parent CPU;
  `replay_native_cases` took 17.867181973 seconds with 0.333035 parent CPU
  and 5.532435 reaped direct-child CPU. Classification took 0.258761494
  seconds. These are actual diagnostic counters, not acceptance or direct
  fsync/I/O accounting. No per-function current loading costs were observed.
- 2026-10-07: The complete source, runtime, archive, Python, Lean and native
  identities match both before/after and the fresh Linux receipt. The same
  4378 full denominator and all 184 selected identities, profiles, SQL,
  native comparisons and current-model verdicts remain unchanged. The
  observer uses the existing verified runtime and explicit pinned Python;
  no source rebuild, production change or phase restart occurred. The new
  ext4 ordinary-file root, all 184 unique actual paths, cleanup, original
  streams, UTC/monotonic boundaries and full host conditions are retained.
- 2026-10-07: Retained all 20 diagnostic raw artifacts and exact public
  helpers in
  [the stage record](../reports/20261007-development-replay-linux-stages/README.md).
  Retrieval session 78288 is terminal, and all 13 original hashes match the
  independent remote inventory. Bounded read-only validation and two stage/
  child-counter corruption checks pass in the pinned environment within
  15-second bounds. The pure helper preflight also preserves return and
  exception behavior. Prior receipts, frozen evidence and the pending clean
  `90ed5e5b` review row remain preserved. Diagnostic evidence review is
  pending. Linux's fresh target miss remains unchanged; the task is not DONE.
  No further diagnostic or optimization is started.
- 2026-10-07: Diagnostic commit `2fc82988263d84cf3799f432d605a9cbf796cbfa`
  passed Claude review `20261007T083225Z-2fc82988`, session 56130 exit 0,
  with zero must findings and one should finding. Named the helper-identity
  and measurement-only comparison exceptions, with their specific reasons.
  All actual input identities and report semantics still compare exactly.
  The reviewer inspected code only; its check launchers needed approval.
  Author bounded checks are terminal successful and pass again after the fix.
  The finding has a fixed journal resolution; refactor review is pending.
  Raw evidence is unchanged.
- 2026-10-07: Refactor `546dfeb9fd9179787f8f33c1cae03147ac7d1f66` passed
  independent Claude review `20261007T083357Z-546dfeb9`, session 88498 exit 0,
  with no findings. The prior should finding has a fixed journal resolution.
  This checkpoint preserves the exact clean review row. The diagnostic
  evidence unit is complete. No native/build/measurement job remains live.
  Both fresh platform receipts and the single Linux stage diagnostic are
  retained without changing the target miss. Loading's current stage CPU is
  observed; its current per-function costs and native wait causes remain
  unobserved. Older per-function profile costs are hypotheses on different
  source, not predicted savings. The coordinator will select any further
  bounded unit; no additional phase or optimization has started. The overall
  task remains IN PROGRESS.
- 2026-10-07: Final stage status/journal checkpoint
  `ec0434a9480e1c24111cea47c3c420fa6c7283af` passed Claude review
  `20261007T083517Z-ec0434a9`, session 20288 exit 0, with no findings.
  The coordinator then authorized one Linux load-only cProfile diagnostic of
  exact measured source `5d15607f`, existing pinned Python and all frozen v5
  bindings. It invokes `corpus.load` once, with no native replay, model
  execution, runtime build or source optimization. Original profile/caller
  artifacts and loaded identity/profile evidence will be retained under the
  unchanged 120-second process-group bound. The actual load is pending.
- 2026-10-07: Public main-guard helper is named `t04c_load_profile.py` and
  cannot shadow Python's `profile` module. Local AST/helper checks precede
  transfer. One transfer used an incorrect temporary-directory name and
  failed with exit 255 before any load. Its original tool output and missing
  original-timestamp limit are retained. The corrected helper transfer is
  terminal successful. Successful preflight compares full source, frozen
  inputs, archive and pinned Python with the fresh Linux receipt. No report,
  native replay or model call has run in this unit.
- 2026-10-07: The single load-only cProfile diagnostic is terminal: session
  98256, exit 0, 4,376 v5 records loaded once with all bindings. It records
  24.757685188 instrumented seconds and 24.688395 parent CPU seconds. These
  are not acceptance or a timing comparison. `expanded_record` has
  10.542457637 cumulative seconds, including 5.270413991 self seconds not
  attributed to an operation. Its canonical pool decoding is 1.074232140,
  serialization 2.292366976, marshal copies 1.482483149 and marshal encoding
  0.267605387 profiled seconds. Stored-record JSON decoding is 5.265636404.
  Full fidelity/acquisition verification remains mandatory and active.
- 2026-10-07: All source, frozen v5, archive, pinned Python and helper hashes
  match before/after and their previous applicable identities. All 122 frozen
  files match the prior complete source manifest. Actual names, count, parts,
  native versions and complete observed/declared profile bindings are retained.
  No native replay, model execution, runtime build or source change occurred.
  Original pstats, full listings/callers, actual UTC/monotonic boundaries,
  full host conditions and original streams are retained in
  [the load-only record](../reports/20261007-development-replay-load-profile/README.md).
  All 24 raw artifact hashes and all 16 retrieved original hashes pass the
  bounded read-only validator. It confirms one profiled corpus load and no
  native/model replay calls, without another load. Evidence review is pending.
- 2026-10-07: The narrow proposed snapshot unit would use fixed canonical
  reference size only for ordinary dict/str inputs after existing validation,
  with the existing serializer fallback for subclasses. All pool/refusal and
  normalization/independence contracts remain required. The reference-only
  time is not isolated, so no saving or acceptance forecast is made. A shared
  normalization cache has unobserved duplicate ratio and adds memory/lifetime
  policy; no cache or new snapshot change is implemented. The coordinator
  chooses any next unit after evidence review. The task remains IN PROGRESS.
- 2026-10-07: Load-profile commit `03da2afb8c047fe0a258a7f820491d9add384821`
  passed Claude review `20261007T085929Z-03da2afb`, session 79488 exit 0,
  with zero must findings and two should naming findings. Named the authorized
  load function and invocation policy, and made the success message use the
  named record-count policy. The reviewer read code only; its validator
  launcher required approval. Author bounded validation is terminal successful.
  Clarified the conditional proposal's actual plain key/string and ASCII
  proof, subtype fallback, source call sites and unseparated cost. No snapshot
  code changed. Both findings have fixed journal resolutions, and bounded validation passes
  again. Refactor review is pending; all raw evidence and the Linux target miss
  remain unchanged.
- 2026-10-07: Load-profile refactor
  `1b21245d91f01ad0f1ee21588ccb266fe88834df` passed Claude review
  `20261007T090220Z-1b21245d`, session 29114 exit 0, with no findings.
  Both prior naming findings have fixed journal resolutions. The reviewed
  load-only evidence unit is complete; its exact clean row is preserved here.
  The coordinator authorized the minimal reference-size fast path after this
  review, without another acceptance phase or profile run.
- 2026-10-07: Bounded expansion now counts a reference without encoding only
  for an ordinary dict, ordinary sole `snapshot` key and ordinary ASCII
  alphanumeric string. The canonical empty-reference length plus string
  length is exact; SHA-256 references are 79 bytes. Every subtype or other
  shape retains the serializer, without an extra subtype iteration. Pool
  digest/shape/reference/membership/unused checks and their order, canonical
  stored/logical limits, JSON normalization, internal marshal-v2 copies,
  independent nested mutable trees and the unbounded default remain intact.
  Independent canonical size and exact/one-byte-short/negative-delta oracles
  include mapping subclasses whose rendering adds escaped Unicode metadata
  and an iteration-sensitive subtype, plus actual shortcut/fallback observation.
- 2026-10-07: All 111 bounded reference, snapshot, storage, shard, tier and
  ownership checks pass in the final suite. Five bounded frozen-binding
  refusal tests pass in 17.64 seconds with the existing pinned runtime.
  Both suites have 60-second bounds. The first combined command omitted that
  runtime path: 108 checks passed and six stopped at setup; no missing
  environment remained after using the already verified path. The historical
  full-phase test was then excluded explicitly; no acceptance/profile phase
  ran. The source-owned test needs no new Nix input module. Frozen corpora
  and all prior raw receipts are unchanged. This small CPU unit makes no
  speed claim: the entire old 2.292-second expander serialization caller also
  includes pool and skeleton work. Independent review is pending. The task
  remains IN PROGRESS.
- 2026-10-07: Reference-size commit
  `3bd80539a8f4af9623fc4d900238dedd0e3ae45a` passed Claude review
  `20261007T091451Z-3bd80539`, session 54105 exit 0, with zero must findings
  and one should docstring finding. Added the bounded-expansion motivation
  and the validated-value caller context to the helper docstring. The body
  and all recorded checks remain unchanged. The author final suite passed
  111 tests in 3.09 seconds, plus the five bounded binding refusals. Finding
  has a fixed journal resolution; refactor review is pending. No performance phase ran.
- 2026-10-07: Reference-size refactor
  `368c27c101a0ec99654e6028f192d0ba74dc47ec` passed Claude review
  `20261007T092019Z-368c27c1`, session 4319 exit 0, with no findings.
  The previous docstring finding has a fixed journal resolution. The checked
  source and all recorded tests remain unchanged.
- 2026-10-07: Read-only retained-profile inspection finds one fidelity
  verification call at 5.087972811 cumulative seconds. Its acquisition call
  is 3.130879275 seconds, with 153,764 required source-instance precision
  and NULL-display checks. The repeated refusal scan is 0.720105865 seconds;
  it does not support a material removal of the remaining target gap.
  A loading worker would need ordered unexpanded JSON transport and parent
  validation; the existing native worker helper does not provide that API.
  No new profile, phase, decoding optimization or loading helper was started.
- 2026-10-07: The coordinator authorized one fixed development-only native
  cap of four on both platforms. The earlier two-worker task wording was our
  implementation checkpoint; the approved semantics require a named small
  bound, the unchanged 120-second process-group guard and the under-30-second
  target. The task now permits at most four before source changes start.
  Retained Linux stage metadata records eight logical CPUs, 62.58 GiB total
  and 58.89 GiB available RAM, load averages 0.564/0.325/0.275, and 34.9 GiB
  free on ordinary ext4. No worker RSS, device contention or speedup was
  observed. The 17.867-second native wall and 5.532-second reaped-child CPU
  values do not identify the wait cause. Four workers are a hypothesis.
  Tiny actual-native clocks, path/order, failure/crash and timeout fixtures
  must exercise four workers. Serial replay, full loading and all acquisition
  and fidelity checks remain unchanged. No acceptance run is authorized yet.
- 2026-10-07: The common development helper now has fixed cap four; its
  executor, serial primitive, ordered exception/path envelope and lifecycle
  are unchanged. Four distinct tiny controlled clocks retain serial native
  evidence and the parent's non-UTC timezone. Mixed failures still report
  the first input while returning paths from the other completed cases.
  Atomic markers confirm four actual workers started before the open-file
  crash check; the private file tree is removed. The configured timeout
  check confirms all four case identities and process IDs in one group,
  then confirms every worker stopped. Ordered crash-envelope tests preserve
  three completed path results and the original first failure.
  The real CLI/report fixture has two authored and the required two synthetic
  cases; it returns four actual cleaned file paths.
- 2026-10-07: Bounded regression session 75347 exited 0: 23 worker, routing,
  tier and source-ownership checks passed in 7.87 seconds. Three separate
  Tcl-capture checks skipped because they require the pinned upstream target;
  none of the worker checks skipped. After making crash markers atomic,
  session 81035 exited 0 with four focused crash/order checks passing in
  0.88 seconds. Outer bounds are 60 and 30 seconds; each configured native
  group-timeout fixture retains its five-second bound. Source files stay
  below 200 lines. Frozen corpora, prior receipts, selection, SQL, profiles,
  full binding validation and the production 120-second guard are unchanged.
  No build, native performance phase, profile, SSH or acceptance run occurred.
  Independent review is pending; the overall task remains IN PROGRESS.
- 2026-10-07: Four-worker commit
  `1726f972315c985b3f6965c4d0c6d7c4b8a319eb` passed Claude review
  `20261007T093857Z-1726f972`, session 57114 exit 0, with zero must findings
  and one should finding. Timeout markers now use atomic pending-file
  replacement, matching the crash markers, so a group kill cannot expose
  partial JSON to the test. The configured five-second timeout is unchanged.
  Focused session 65065 exited 0: one group-timeout check passed in 5.67
  seconds under a 20-second outer bound. All four actual identities and
  process IDs are retained and stopped. The finding has a fixed journal
  resolution; the test-only refactor review is pending. No performance run,
  source decoding change or new acceptance occurred.
