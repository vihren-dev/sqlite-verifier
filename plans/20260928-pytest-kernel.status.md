# Kernel pytest conversion status

Created: 2026-09-28. Status: DONE (bounded kernel conversion).
Task: [Discoverable tests and cached project builds](20260928-pytest-nix-builds.task.md).
Decision: [ADR 0001](../docs/adr-0001-pytest-and-nix-ci.md).
Workspace: sqlite-verifier-adr1-atuin. Base: 9fc0eabd. Reviewer: coordinating technical lead.

Replaced the sequential kernel gate script with independently selectable cases
covering all eighteen baseline scenarios and the accepted task's explicit partial
proof attack. Session setup compiles only harmless checked-in common fixtures;
each case mutates a private writable copy. Selected runtime paths supply the
compiler, library and checker. Exact acceptance/refutation exits, named protected
substitution diagnostics, initializer sentinel absence, and existing compiler
30s/checker 60s deadlines remain. Production proof checking is unchanged.

Pinned pytest 9.1.1 collected nineteen cases in 0.02s with no compiler execution:
`timeout 15 python3 -m pytest tests/kernel_gate_test.py --collect-only
--catalog-json build/kernel-catalog.json -q`.
Collection also passed in 0.01s with `--runtime-root /missing-kernel-runtime`,
confirming runtime resolution remains deferred to execution.

Execution uses the existing pinned shell and immutable B1 runtime documented in
[Atuin status](20260928-pytest-atuin.status.md), after the other native suites
finished. The first run passed all eighteen baseline cases; the newly added
partial fixture expected the wrong diagnostic. Lean elaborated a nonrecursive
`partial def` to an ordinary body, which was rejected by target reconstruction.
The replacement deliberately constructs a `.partial` definition. Pinned
`Lean/Replay.lean` skips partial constants, so the exact required diagnostic is
`missing required declaration: Proofs.migrationCorrect`. No checker change is
needed. The corrected full run passed nineteen cases in 63.47s:
`timeout 1500 python3 -m pytest tests/kernel_gate_test.py --runtime-root RUNTIME
--runtime-variant source --suite kernel-all-fixed -vv --durations=20`.
Each of the nineteen actual collected node IDs then passed when selected in its
own pytest process with the same runtime arguments and a 180s command deadline
(132.49s combined). All nineteen passed in reverse collection order in one process
(60.32s). The session common setup remained unmodified across all private copies.

Exact command observations are in `build/kernel-individual-commands` and
`build/kernel-reverse-command`, with standalone timings in
`build/kernel-individual-results.json`. JUnit/JSON reports are in
`build/test-results/source/kernel-*`. The final test module has 185 lines, no
script entrypoint, and no changes to proof semantics, production code or limits.
