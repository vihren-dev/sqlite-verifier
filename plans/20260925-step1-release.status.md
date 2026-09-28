# Step 1 release status

Created: 2026-09-25. Status: DONE (2026-09-28).
Task: [step1-release.task.md](20260925-step1-release.task.md).
Starting implementation: 0c5bb79e. Local full just test passed; current GitHub
main is e094a5ff and the published preview is v0.1.0-rc.1.

Owner explicitly approved the current state and requested completion of Step 1.
Coordinator owns integration and publication; independent technical review covers
release inputs and packaging. Existing Step 1 source, contracts and acceptance
requirements remain in force with the owner-approved preservation-only correction.
No release is claimed complete yet.

2026-09-25 release preparation: refreshed README, release/install/CI notes, Atuin
acceptance record, roadmap v0.2 and the Step 1 task/status. The owner's explicit
acceptance is recorded separately from unmeasured historical human effort. Current
code has independent Ultra technical-lead release review: no implementation or
packaging blocker. Both supported parsers and installed Atuin checks are included;
removed modules cannot enter archives via stale build outputs. Documentation links
pass. No semantics changed since the passing full local check at 0c5bb79e.

GitHub ruleset 23934665 remains active, with owner user6329237 as the existing
audited bypass actor; authenticated owner identity confirmed. Intentional protected
baseline changes are explicitly approved in this conversation. Final integration
will use that authorization without changing the ruleset or baseline workflow.

Integrated 7bc10f9978369f7bcd40aada73af774fc1081726 into public main using the
existing owner bypass; GitHub recorded the protected-branch override. The exact
new revision passes local self-consistency checks for all three protected example
baselines. Hosted CI run36137322748 began complete package checks on both platforms.

macOS exposed a harness deadline defect: the 2,000-column limit-before-duplicate
comparison exceeded the per-file 30-second Lean deadline. No assertion failed.
Evidence: build/step1-macos-coverage/coverage.json and step1-macos-job.log.
Independent Ultra reviewer recommends only 90 seconds per concrete proof file,
retaining the 30-second negative test, 180-second collector and 420-second aggregate
bounds. Existing full native/model comparison and false-empty negative passed
locally after this adjustment (build/step1-model-budget.log, exit0). No proof,
semantics or admitted domain changed. Fresh hosted package checks will validate
the repaired harness; the failed run is not passing release evidence.

Hosted full package run36138251243 PASSED on e850287697ea883ddfd3fc832860da340bb493ca:
aarch64-darwin23m28s, x86_64-linux18m33s. Both jobs passed the complete source
suite, built native archives, installed them offline in isolated environments,
and passed the real installed-entrypoint and Atuin checks. Logs and structured
result: build/step1-{macos,linux}-package.log and step1-package-result.json.
Artifacts were uploaded on both platforms. The duplicate ordinary run36138213594
was explicitly cancelled in favor of this full package run at the same revision.

Documentation-only preparation for v0.1.0 now records those results. Runtime
code remains exactly the checked e8502876 implementation. The next gate is the
version-tag workflow and verification of its published native assets/checksums.

Tag v0.1.0 at8fb4f2d3 did not pass its macOS release check: the forged-kernel-body
fixture exceeded the checker process's30-second harness deadline. The successful
earlier run remains valid evidence but cannot override this failed publication
gate. Its tag is preserved. The owner requested CI performance work from the
timing report while that run was active; see
[CI performance status](20260925-ci-performance.status.md). The next immutable
release tag will be v0.1.1 after the fixes pass both hosted platforms.

2026-09-28: sequential macOS full source checks passed at54ea013a, but the installed
positive still exceeded the production checker deadline (run36144746026).
Release remains pending. CI work now fixes repeated imports within the gate,
preserving all proof checks and the30s production limit; see the performance
status for controlled measurements and independent review.

Full package run36387285239 PASSED on7a99c71f40c66077b2293e1ce2c8ef3151ce5d67:
macOS14m31s andLinux9m57s, including every real installed-runtime/Atuin case at
the unchanged30s production checker deadline. Created fresh tagv0.1.1 at that
exact revision; release run36388588408 repeats both platforms and gates publication.
The failed v0.1.0 tag is preserved. No approval policy or product contract changed.

Closeout, 2026-09-28: release run 36388588408 PASSED on the exact tag revision:
macOS 14m17s, Linux 8m46s, publication 1m5s. Stable
[v0.1.1](https://github.com/vihren-dev/sqlite-verifier/releases/tag/v0.1.1) was
published at 07:07:27 UTC. Exactly two native archives and two checksum files are
uploaded; downloaded checksum files match GitHub's archive SHA-256 digests:

- aarch64-darwin: 1,124,611,568 bytes;
  ff8bd547ee88fbe1cc82312143c4fcaa6214da89b4490379eb10092e48b39913
- x86_64-linux: 1,016,723,322 bytes;
  012445a4eadc8398d9d031d4c57ae1bc2a1d4ca75da059f58e941bd93f90095c

The publisher independently checked the downloaded complete archives before
uploading them. Both platform runs built, installed offline and exercised the
actual runtime. Evidence: build/ci-import-reuse-release-{macos,linux}.log,
ci-import-reuse-release-result.json, release-v0.1.1.json and downloaded checksums.
README, roadmap, acceptance review and task records now reflect completion.
No new product-owner input is required; Step 2 remains future work. Task DONE.
