# CI performance status

Created: 2026-09-25. Status: DONE (2026-09-28).
Task: [ci-performance.task.md](20260925-ci-performance.task.md).

Read the owner's timing report and traced baseline compilation and aggregate
checks. Starting revision8fb4f2d3; clean working copy. The report's full-package
baseline is23m38s overall, with tests dominating both platforms. Work preserves
all source and installed coverage. Coordinator owns integration, cache policy,
measurements and release records; bounded independent implementation/review follows.

2026-09-25 implementation: complete sealed source hashes are checked against the
optional protected baseline before module compilation. Matching inputs retain
all compiler and independent kernel stages. Regression proves transitive
membership, drift/error precedence and immutable source/schema snapshots. It
passed locally in14.15s after removing a duplicate positive case already covered
by the ordinary CLI suite. Existing compilation isolation suite passed in28.062s.

Kernel and ordinary CLI suites now overlap using two workers, unchanged360/600s
suite deadlines, isolated files and retained complete logs. Actual local pair
passed in187.03s (CLI156.02s). Runner regression verifies overlap, failure/timeout
propagation and awaited siblings. All37 Python unit checks passed in8.461s in the
pinned environment. A sandboxed host-Python installer unit attempt lacked Nix
socket access; the complete rerun inside the authorized pinned environment passed.

Added exact platform+flake-key Nix dependency caching, successful-main-only saves,
no fallback/extra paths/purge/GC, fixed upstream v7 commit. Added runtime copy,
export, signature, compression and installation timings; installed Atuin cases
stream live. Signature checks, archive size guard and every installed case remain.
Independent Ultra review found no trust-boundary or correctness blocker. The
original v0.1.0 tag's macOS forged-body checker timed out at30s; Linux passed in
18m43s and publication was skipped. Only test checker invocations now allow60s;
compiler and production CLI deadlines remain unchanged. Both-platform full cold
and warm package measurements remain required before completion.

Source Atuin public CLI suite passed in the same pinned environment: both
positive migrations and every existing negative case. Evidence: build/ci-atuin-local.log
and exit0. Documentation checks passed; no approved contract bytes changed.

Local instrumented archive experiment found the remaining construction cost:
xz payload copying19.22s, Nix export274.73s, signature/content verification3.97s,
outer gzip24.53s. Changing only Nix's supported export compression to zstd gave
copy21.07s, export9.80s, verification0.69s, outer gzip28.30s. Final archive is
1,127,206,947 bytes, under the2GB guard. This is a local controlled experiment,
not a hosted end-to-end speedup claim. Native installation/Atuin validation
passed before committing the one-line export setting. Independent compatibility
review confirms installers delegate decoding to Nix metadata; all-content and
signature checks remain enabled. No installer or trust-policy change is needed.

The zstd offline installed runtime PASSED all native parser, isolated CLI and
Atuin cases (installed Atuin113.45s); extraction/installation22.53s. Logs:
build/ci-runtime-zstd-{local,installed}.log, both exit0. The final export setting
is now the ordinary Nix URI compression parameter; no codec/installer abstraction.

Hosted experiment run36143187396 at0cef4339: Linux complete package PASSED in
11m46s including cache save; pair160.16s (CLI127.46s, kernel160.15s). macOS
FAILED because overlapping suites made a valid production CLI checker exceed30s;
kernel completed328.38s. This is failed experimental evidence, not acceptance.
The runner therefore retains2workers only on Linux and uses1on macOS, preserving
all production and suite deadlines. Two focused real-process runner regressions
passed in1.764s, including serial continuation after a sibling failure. Linux's
new dependency cache exists; macOS did not save a cache from its failed job.
Final revision needs both-platform complete validation and a repeated warm run.

2026-09-28: run36144746026 at54ea013a passed Linux complete packaging in12m31s
with a14s Nix cache hit and1.02s zstd export. Sequential macOS source suites passed
but the first installed positive hit the unchanged30s checker deadline. This is
failed acceptance evidence; overlap was not the sole cause. Native profiling
showed repeated library imports and comparisons dominate. ProofChecker now threads
ImportState through the four stages within one invocation, retaining all checks.
Independent Medium source review approved the trust boundary. The initial empty
state uses Lean's public `default`, matching ImportStateM.run; no private constructor.
Same-fixture native profile: original17.582s then10.656s; reuse2.599s then2.475s.
The first original sample includes colder filesystem state; no global cache or
production deadline increase is introduced. Full adversarial/source validation
and both-platform package measurements remain pending.

Local validation passed before integration: full library/checker build, fresh
native/model coverage, environment snapshot identity, parser incremental checks,
schema generation, ordinary CLI (76.40s), full kernel attack suite, compilation
isolation, early baseline (16.55s), all13 Atuin cases, coverage validation and
38 Python unit tests (10.042s). Logs: build/checker-reuse-check.log,
checker-reuse-check-rest.log and checker-reuse-check-final.log (final exit0).
The first kernel test run rejected a substitution earlier during import; its four
assertions now require the exact protected name and either duplicate-import or
protected-modification rejection. Independent Medium review approved this change;
the final complete attack suite passed. Production and suite deadlines unchanged.
The aggregate documentation scan encountered unrelated uncommitted ADR drafts
and an active editor lock. Those files remain untouched and excluded from this
commit. The same Markdown validator passes against the full publication file
set, including changed documentation. Hosted clean-checkout validation is next.

Integrated7a99c71f40c66077b2293e1ce2c8ef3151ce5d67 into public main using the
existing owner-authorized bypass; no rules changed. Hosted run36387285239 performs
complete package checks on both platforms. Independent Ultra aggregate review of
8fb4f2d3..7a99c71f found no additional coverage, cache, archive/install or release
blocker; the checker itself had separate independent Medium review.

Run36387285239 PASSED at7a99c71f: macOS14m31s (cold dependency cache, first save),
Linux9m57s (warm dependency cache). Every source and installed case passed.
Pair times168.25s sequential macOS and81.34s concurrent Linux; exports6.10s/0.89s;
installed Atuin112.84s/119.58s. Evidence: build/ci-import-reuse-{macos,linux}.log
and ci-import-reuse-result.json. Fresh tagv0.1.1 points at this exact revision;
run36388588408 repeats full packaging on both platforms before publication.

Closeout, 2026-09-28: the same-revision release repeat PASSED: macOS 14m17s,
Linux 8m46s, publisher 1m5s. Both dependency caches hit; macOS restore took about 45s.
The second macOS installed Atuin run took 161.38s versus 112.84s in the first run,
illustrating runner variability despite identical source and assertions. Linux's
second suite pair took 73.44s and installed Atuin 104.28s. Both platform jobs retain
all source, kernel, native/model, archive and installed-runtime coverage.
Against the original 23m28s/18m33s jobs, observed improvements are 38–39% macOS and
46–53% Linux. No promise of fixed future durations is made. The results and failed
experiments are recorded in docs/ci-performance.md. Release v0.1.1 is published;
both checksum assets match GitHub's uploaded archive digests. Task DONE.

Final documentation validation passed against the complete publication file set;
all four CI routing checks passed in 0.357s. Only completion records and release
links change after the tested tag. Unrelated local ADR drafts remain excluded.
