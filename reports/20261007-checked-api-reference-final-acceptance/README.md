# Checked API reference integration acceptance

Created 2026-10-07. Audience: team and reviewers.
Task: [T18b](../../plans/20261006-checked-api-reference.task.md).

The corrected published head is `d7e5e950`. Local acceptance differs only
in its status file and appended review journal. No production or test input
changes while acceptance runs. The complete `just test` command exits zero
in pinned native macOS environment, session 43812. Its original source XML
records 410 passing tests and 35 passing subtests, with no failure or skip.
The 95 Nix checks are excluded from this source command and run separately.

All seven development Nix suites run in hardened sandboxes and pass 310
checks: 12 Atuin, 42 bundle, 14 CLI, 126 harness, 28 kernel, 12 sample and
76 upstream. Each suite has a 1,200-second guard and each test has a
300-second guard. The enclosing development build has its existing
900-second limit. Original XML, complete compressed command output and
resolved Nix output identities are retained. Model and frozen suites are
outside this development command; full hosted Linux acceptance remains
separate.

The rebuilt documentation inventory checks all 259 authored items. The
actual proof runtime output has 53 store paths, with no documentation
generator or reference artifact. Its original closure query is retained.
The configured Linux host does not contain this integration's exact
runtime output, so no actual Linux output closure is claimed here. Both
previous native derivation graphs exclude documentation dependencies.

The corrected hosted macOS job succeeds in CI `37667476876`. Its reference
ZIP matches artifact digest `316c7962249130b45575b3e1585fc403e4e5f67635e93fdea30866832a0499c9`.
The original reference receipt identifies actual merge source `ca7280a8`,
21 modules, 323 public declarations, 1,167 HTML pages and 829,618 valid
local links. The inventory checks all 259 authored items. The full ZIP
remains in the build directory and hosted artifact; its two original JSON
records are retained here. The inventories are compressed without changing
their original bytes; the receipt binds both stored and original hashes.
The earlier Linux failure remains unchanged.

`receipt.json` binds original artifacts and exact output identities.
The separate macOS Nix infrastructure command terminates with exit zero:
95 checks pass in 122.51 seconds under its existing 600-second limit.
Original XML and the complete compressed output are retained. This verifies
actual input ownership, dependency invalidation and source boundaries.
Hosted Linux acceptance remains in progress. T18b remains IN PROGRESS.
