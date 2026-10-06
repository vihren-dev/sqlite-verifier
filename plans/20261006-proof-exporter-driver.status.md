# Proof exporter driver status

Status: IN PROGRESS. Created 2026-10-06.

Task: [proof exporter driver](20261006-proof-exporter-driver.task.md).
Source: [issue #29](https://github.com/vihren-dev/sqlite-verifier/issues/29).

## Progress

- 2026-10-06: Preserved the replay-headroom workspace unchanged while its
  deadline specification question awaits owner feedback. Inspected the idle
  catalog workspace; it was clean after the reviewed catalog task. Started
  a new change there from reviewed Lean 4.34.1 revision `6917e3c8`.
- 2026-10-06: Read the approved T02 card and actual issue #29, which has no
  comments. Read the installed exporter invocation, source/contract discovery,
  bundle checker, trusted-base construction and Nix dependency/runtime graph.
  Created the task before feature changes. Root is running a separate native
  check, so exporter builds and measurements await an idle slot.
- 2026-10-06: The checker base is `SqliteVerifier` plus trusted external
  imports. Approved contract and generated input modules are replayed
  separately and must not be treated as omitted library modules. Candidate
  source discovery already distinguishes installed `.olean` imports from
  caller-owned source modules without using a namespace-prefix test.

## Validation

Pending: pinned upstream API audit, exact origin/closure design, focused
tests, byte-identical native baseline comparisons, installed runtime checks
on both platforms, independent review and required owner review.
