# Independent review of each commit by the other agent tool

Created 2026-10-06. Status: in progress.
Status file: [status](20261006-review-process.status.md).
Related: the writing and proposition rules in [`AGENTS.md`](../AGENTS.md); issues #18, #21, #22, #23, #31.

## Observable behavior when done

- `just review [REVISION]` reviews one commit (default `@-`, the commit before
  the working copy) against a fixed checklist, `docs/review-checklist.md`, and
  prints the review.
- The reviewer is the other agent tool: a call from a Codex session uses Claude
  Code, a call from a Claude Code session uses Codex. A call with no agent
  session (a person in a terminal) uses Codex. `REVIEWER=claude` or
  `REVIEWER=codex` overrides the choice.
- If the caller's environment has the session markers of both tools and no
  override is given, the command stops and asks for `REVIEWER`, instead of
  guessing.
- The reviewer starts without the session markers of either tool, and with a
  recursion guard: `just review` inside a review stops at once.
- The reviewer only reads the repository. It reports only violations of the
  listed conditions, in a fixed line format, or `No findings.`
- Exit codes: 0 = review complete, no "must" findings; 1 = "must" findings;
  2 = usage error (unknown reviewer, both tools detected, nested review,
  unknown revision); 3 = the reviewer failed or its output has no recognizable
  findings and no `No findings.` line.
- `AGENTS.md` requires an agent to run `just review` after each commit whose
  checks pass, and to handle the findings.

## Tests

- Unit tests for the pure parts: reviewer selection from an environment
  mapping, the sanitized reviewer environment, the reviewer command line, and
  the parsing of review output (findings, `No findings.`, malformed output).
- An integration test that runs `tools/review.py` with stub `jj`, `codex` and
  `claude` executables on `PATH`: it checks the selected tool, the stripped
  markers, the guard variable, the instructions on standard input, and the exit
  codes. Every subprocess call has a timeout.
- One manual run of each real reviewer on a commit of this change, recorded in
  the status file. It is not an automated test, because it needs credentials and
  network access.

## Tricky points

- Session markers are inherited: a tool started by the other tool sees both sets
  of markers. Detection uses `CLAUDECODE` for Claude Code and `CODEX_THREAD_ID`
  for Codex; neither is a documented interface, so a change in either tool must
  fail visibly, not select the wrong reviewer silently.
- Removing markers must not remove configuration that the reviewer needs
  (for example `CODEX_HOME`).
- The repository is a colocated jj/git repository: `codex review --commit`
  takes the git commit hash of the jj revision.
- The checklist holds the conditions; `AGENTS.md` only holds the rule to run the
  review, so that agents do not load the checklist in every session.
