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
