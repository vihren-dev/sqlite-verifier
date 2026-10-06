# Status: independent review of each commit

Created 2026-10-06. Status: in progress.
Task: [task](20261006-review-process.task.md).
Relevant files: `tools/review.py`, `tests/test_review.py`, `docs/review-checklist.md`,
`justfile`, `AGENTS.md`.

## Progress

- 2026-10-06: task and status files.
- 2026-10-06: `tools/review.py`, `tests/test_review.py` (17 tests, all pass in
  about 1 s, no credentials needed) and `docs/review-checklist.md` (conditions
  R1-R13 and the output format).
- 2026-10-06: `just review` recipe and the "Review after each commit" rule in
  `AGENTS.md`.
- 2026-10-06: first real run (`just review` from Claude Code, reviewer Codex)
  failed with exit code 3: `codex review --commit` rejects custom instructions.
  Fixed: Codex reviews run as `codex exec --sandbox read-only --ephemeral -`.
- 2026-10-06: second real run, Codex reviewing commit `39e069d` (the script):
  well formed, about 60 s, 1 must and 4 should findings.
  - R11 must (the command the real CLI rejects): already fixed by the commit
    above. Added a test that runs each installed CLI's option parser with
    `--help`. Limit, recorded here and in the test: it finds renamed or removed
    options, but not argument conflicts, which the CLI checks only without
    `--help`. The original bug was such a conflict; only a real run finds it.
  - R1 should (session-marker names and the `jj` timeout were literals): fixed,
    now named constants with reasons.
  - R9 should (`resolve_commit` gave no reason): fixed.
  - R10 should (reviewer failure gave no next step): fixed.
