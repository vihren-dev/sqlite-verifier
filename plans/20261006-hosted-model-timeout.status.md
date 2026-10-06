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

Retain and compare original hosted logs, identify the cause, implement only a
justified complete bounded check path if needed, run meaningful cheap checks and
independent reviews, and obtain actual hosted model completion. Temporary T03
platform acceptance still needs exact hosted Linux/local Darwin evidence links.
