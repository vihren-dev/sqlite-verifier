# Unit cache report retention — 2026-09-28

Task: [pytest/Nix builds](20260928-pytest-nix-builds.task.md), accepted ADR0001.
Bounded followup requested by root; review: formal_preservation and root.

DONE: cache selection now requires readable well-formed source/unit.xml before
returning any excluded IDs and retains that JUnit artifact beside JSON reports.
Repeated runs safely replace only known generated cache-report targets, including
prior read-only Nix copies; only their two generated parent directories receive
owner write/execute permission. Unknown files and the immutable cache source remain
untouched. The CI driver independently stops pre-copying the same reports.

Validation: all 16 focused orchestration/cache-selection scenarios pass in 0.08s,
including actual 0444 files/0555 directories on rerun and missing-JUnit rejection
before any destination is created. No Lean, native runtime or full acceptance run
was performed in this helper-only followup. Final inventory reconciliation remains
in progress in the separate inventory status.

Independent static review by formal_preservation approved this exact helper and
regression-test delta; validation precedes exclusions and source artifacts remain
unchanged. Root owns final integrated acceptance.
