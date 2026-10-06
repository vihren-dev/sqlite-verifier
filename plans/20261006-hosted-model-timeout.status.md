# Hosted macOS model-suite timeout status

Status: IN PROGRESS. Created 2026-10-06.

Task: [hosted model timeout](20261006-hosted-model-timeout.task.md).
Workspace: `sqlite-verifier-hosted-model-timeout`.
Bookmark: `codex/hosted-model-timeout`.
Base: public main `29d2ed7ab7621373e5bb33c97ce8c325fad1b41f`.

## Progress

- 2026-10-06: Created a separate Jujutsu workspace/bookmark for the explicitly
  authorized timeout investigation. Frozen PR branches are unchanged. T18b
  native acceptance is retained separately at `d066779c`; its public source is
  `dac12b49`, and its remaining acceptance is hosted CI artifact retention.
  No heavy native rerun is authorized while PR #48 holds both host leases.
- 2026-10-06: Retrieved current PR metadata read-only. PR #43 source is
  `6917e3c8`, PR #44 is `d08d91ee`, and PR #47 is `07dc71b3`. Actual hosted logs
  and cache/test progress must establish the deadline and cause before code
  changes. Public main's shared pytest recipe currently uses a 420-second
  timeout; the reported 600-second cutoff must be located in the executed job.

## Acceptance remaining

Complete independent review, publish the authorized separate draft PR and obtain
actual hosted model completion. The 600-second proposal is not yet measured.
T03's hosted macOS result and its separate owner/release gates remain open.

## Checked investigation

- 2026-10-06: Retained five complete decoded hosted job logs with original and
  compressed SHA-256 bindings. Actual model deadline is 420 seconds; 600 seconds
  belongs to later host checks. PR #43, #44 and main time out near the final
  cases with exit 124 and no model JUnit. PR #47 freshly runs all 323 cases,
  322 passed/one Tcl skip in 300.70 seconds. PR #43 hosted Linux passes the same
  count in 222.42 seconds. Exact head/merge/runtime identities and temporary
  T03 platform evidence are in the [report](../reports/20261006-hosted-model-timeout/README.md).
- 2026-10-06: The ordered 32-file ownership list is identical in all four
  checkouts. Progress and both final test files are byte-identical. Buffered
  logs cannot isolate why execution speeds differ; the measured historical
  work and repeated frozen loads explain the aggregate budget pressure.
  Only the full model deadline increases to 600 seconds, approximately twice
  the measured passing macOS time. Six other deadlines, all cases, subprocess
  limits and complete report flags remain unchanged.
- 2026-10-06: Real Nix command/ownership evaluation and existing CI scope/check
  tests pass: 10 cases plus 28 subtests in 1.49 seconds. No heavy native rerun
  or frozen-branch change occurred. Independent review and the authorized
  separate draft PR still follow. The new hosted model result is required
  before this task can be DONE.
- 2026-10-06: Both native-system flake projections reuse all seven real test
  targets (two evaluation checks, 6.53 seconds). Markdown local links resolve.
  All five compressed logs reproduce their retained decoded bytes and hashes;
  four source comparisons preserve the same complete 32-file model inventory.
