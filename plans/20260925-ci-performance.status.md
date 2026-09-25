# CI performance status

Created: 2026-09-25. Status: ACTIVE.
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
