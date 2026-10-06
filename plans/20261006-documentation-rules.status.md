# Status: checked public documentation rules

Created 2026-10-06. Status: DONE.
Task: [task](20261006-documentation-rules.task.md).
Source: public issue #26 and its plain-words proposition comment.
Relevant files: `AGENTS.md`, `docs/review-checklist.md`.

## Progress

- 2026-10-06: read the issue and its comment, and checked the existing writing
  and proposition rules. Created the task and status files before editing.
- The API docstrings, walkthrough and generated reference remain separate
  work in #26. This task completes only its repository-rule requirement.
- 2026-10-06: added user-directed Verso rules for public declarations and
  fields, with the same-commit documentation requirement, checked names,
  examples and definitional assertions. The forward-reference limitation
  states both permitted placements. Existing plain-words rules are preserved;
  declaration names now use checked references.
- 2026-10-06: checked the wording against issue #26 and its comment. No source
  declaration changed, so no Lean build or new behavioral test is needed.
- 2026-10-06: Claude independently reviewed commit `0e6b479d` through
  `REVIEWER=claude just review`: no must or should findings, exit 0.
  The append-only review record is `20261006T083446Z-0e6b479d`. The rules portion
  is DONE; issue #26 stays open for the existing API and reference work.
