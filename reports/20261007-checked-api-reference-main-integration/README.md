# API reference integration with delivered main

Created 2026-10-07. Audience: team and reviewers.
Task: [T18b](../../plans/20261006-checked-api-reference.task.md).

The unpublished reference branch includes accepted main `923b7cee`. The
three original review journals remain ordered subsequences of the merged
journal, including repeated rows. `journal-preservation.json` records each
original hash and count and the verified result.

The reference Lean sources, tooling and pinned dependencies have no changed
file against successful native source `2df58fd1`. Its original native
reference receipts remain valid for their original source and revision.
This integration does not claim a new native reference execution.

The workflow builds and retains the reference on both native platforms for
non-documentation scopes, including PRs. Runtime checks retain their existing
platform guard. The 105-minute job budget accounts for the existing
1,800-second reference phase without changing child timeouts.

The retained bounded XML records 54 passing workflow, routing, reference,
CLI and inventory checks and 35 passing subtests. Twelve native or Nix checks
are explicitly deselected. `receipt.json` binds the raw files and these
counts. Local expensive checks remain on hold at the resource guard. Hosted
reference artifacts, ordinary acceptance and normal delivery remain required.
