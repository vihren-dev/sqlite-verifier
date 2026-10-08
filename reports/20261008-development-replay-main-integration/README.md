# Development replay integration checks

Created 2026-10-08. Audience: team and reviewers.
Task: [T04c](../../plans/20261006-development-replay-headroom.task.md).

Integration combines reviewed feature `584f4c8e` with accepted main
`d75fdc2b`. All six measured production files and frozen v1-v5 corpus bytes
remain unchanged. Delivered transaction code, tests and evidence remain
unchanged. Nix ownership includes both delivered transaction inputs and
new loading workers. The three original review journals are ordered
subsequences of the combined journal, including repeated rows.

Bounded integration checks pass 136 tests in 9.04 seconds, with one explicit
deselection. Actual Nix ownership checks pass 11 tests in 26.94 seconds,
with 46 deselections. Original XML, source hashes and journal preservation
records are retained here. `manifest.json` binds each original file.
The standalone receipt validator and all five corruption checks also pass.
No timing phase runs for this integration. The passing standalone phases
remain bound to their original reviewed source, `2006755a`.

Integration review `20261008T071836Z-886de497` has no findings.
Fresh final macOS Nix sandbox execution passes 135 harness checks in
3.82 seconds and 22 sample checks in 37.26 seconds, without skips or failures.
Original XML and the complete console log are retained. The exact outputs are
`/nix/store/73gsfgxfpph44bk4gvvqknnfvi584cza-sqlite-verifier-test-harness-1`
and `/nix/store/9fqsb2glgy0k7d6s9zz3jrpyhp792yvl-sqlite-verifier-test-sample-1`.
These are suite durations, separate from standalone replay acceptance.
Independent final-evidence review and publication remain required. T04c is
IN PROGRESS.
