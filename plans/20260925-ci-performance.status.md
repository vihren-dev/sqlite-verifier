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
