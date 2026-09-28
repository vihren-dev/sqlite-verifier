# Atuin pytest conversion status

Created: 2026-09-28. Status: DONE (bounded source Atuin conversion).
Task: [Discoverable tests and cached project builds](20260928-pytest-nix-builds.task.md).
Decision: [ADR 0001](../docs/adr-0001-pytest-and-nix-ci.md).
Workspace: sqlite-verifier-adr1-atuin. Base: 5f448260. Reviewer: coordinating technical lead.

Replaced the sequential Atuin script with thirteen independently selectable cases.
Every case copies its own complete Atuin example through the shared example_factory.
The alternative-column case creates both changes directly and derives expected
approved hashes from the protected baseline. Public status/exit agreement, exact
input hashes and generated artifacts, named drift diagnostics, and non-timeout
proof rejection assertions remain. The shared runner supplies the selected source
or installed runtime environment and command diagnostics.

The old script entrypoint is removed; the coordinator updates justfile and the
installed harness before integration. Installed archive execution remains part of
the main task, using these same thirteen node IDs.

Initial execution against B1 immutable runtime yielded 1 passed and 12 failed in
27.38s. The original preservation case verified; all mutation cases failed before
CLI invocation because example_factory preserved Nix-store read-only file modes.
Reported the shared mutable-copy fixture defect to its owner; no runtime/store
permissions changed. Further execution paused pending the shared fix.

Rebased onto reviewed helper fix 5f448260, which creates writable private copies
while preserving executable bits. After `python3 tools/check_resources.py` passed,
entered `nix develop path:./nix -c bash --noprofile --norc` once. Python 3.14.7 and
pytest 9.1.1 used the immutable runtime at
`/nix/store/vzpcnwzpxgd31pl35g1qf8ziqasxsfav-sqlite-verifier-runtime-1`.

`timeout 15 python3 -m pytest tests/atuin_cli_test.py --collect-only
--catalog-json build/atuin-catalog.json -q` collected exactly thirteen cases in
0.01s. `timeout 1500 python3 -m pytest tests/atuin_cli_test.py --runtime-root
RUNTIME --runtime-variant source --suite atuin-all-fixed -vv --durations=20`
passed all thirteen in 120.49s. Each collected node was then selected in its own
pytest process with the same runtime arguments and a 180s command deadline:
thirteen passed, 124.85s total. Finally all collected node IDs were passed in
reverse order to one pytest process: thirteen passed in 114.83s.

Full commands, streams and timings remain in `build/atuin-individual-commands`,
`build/atuin-individual-results.json`, and `build/atuin-reverse-command`.
JUnit and JSON reports are under `build/test-results/source/atuin-*`.
No Lean sources, proof semantics, installed runtime, or production deadlines changed.
