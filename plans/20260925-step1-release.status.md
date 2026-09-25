# Step 1 release status

Created: 2026-09-25. Status: ACTIVE.
Task: [step1-release.task.md](20260925-step1-release.task.md).
Starting implementation: 0c5bb79e. Local full just check passed; current GitHub
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
