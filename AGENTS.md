# Agent instructions for sqlite-verifier

The workspace rules in the parent directory's `AGENTS.md` also apply. This
file adds rules that are specific to this repository.

## Writing style

All text in this repository follows these style guides:

1. [ASD-STE100 Simplified Technical English](https://www.asd-ste100.org/):
   its writing rules. Its dictionary is not required.
2. [Google developer documentation style guide](https://developers.google.com/style):
   for everything ASD-STE100 does not cover, including error messages and how
   to refer to code, files and commands in text.

When the two conflict, ASD-STE100 applies.

"Text" means documentation, comments, docstrings, commit messages, and strings
that users see: CLI output, diagnostics and error messages.

Rules for this repository:

- Write each document for one audience: users (README, installation,
  examples), designers and reviewers (ADRs, trust boundary), or the team
  (status and acceptance records). Do not mix them in one document.
- A docstring tells what the code does and why. Use a negative statement only
  to warn about a real trap.
- An error message tells what failed, where, and what the user can do next.
  Do not refer to internal documents, such as ADR numbers, in user-facing text.

## Propositions in plain words

A proof certifies only the formula as written. If the formula says less than
intended, verification still succeeds. The plain-words statement is where a
reader checks that the formula and the intent agree.

- Each proposition in the core library and the public API has a docstring that
  restates it in plain words: each `def` or `abbrev` of type `Prop`, each field
  of type `Prop` in a structure, and each theorem statement. A small internal
  helper lemma needs one sentence.
- The words say what the formula says, not what it is meant to say. Include
  the quantifiers, what is assumed and what follows, and each case in which
  the formula requires nothing. If the formula is weaker than the intent, say
  so.
- The structure of the text follows the formula: one item for each conjunct or
  case.
- A change to a formula changes its plain-words statement in the same commit.
- Proofs need no restatement: the kernel checks them, and trust does not
  depend on them. Exception: a library theorem that other proofs use, or a
  proof longer than about 20 lines, has a short proof sketch (1-5 sentences)
  in its docstring. The sketch describes the strategy and the key idea, not
  each step.

## Review after each commit

An independent reviewer checks each commit against
[`docs/review-checklist.md`](docs/review-checklist.md). The reviewer is the other
agent tool: Codex reviews commits from Claude Code sessions, and Claude Code
reviews commits from Codex sessions.

- After each commit whose checks pass, run `just review`. It reviews `@-`, the
  commit before the working copy. A commit that changes only files in `plans/`
  needs no review.
- Exit code 0: no "must" findings. Fix "should" findings, or record each one
  with a reason in the status file.
- Exit code 1: fix each "must" finding in a `refactor:` commit before the next
  feature commit, and review that commit too. After two review rounds with new
  "must" findings, stop and report to the owner.
- If you disagree with a finding, record the finding and the reason in the
  status file. Repeated disagreements show that the checklist needs a change.
- Exit code 2: the command cannot choose a reviewer or revision; follow its
  message (for example, set `REVIEWER=claude` or `REVIEWER=codex`).
- Exit code 3: the reviewer failed or gave no recognizable result. Run the
  review once more; if it fails again, record it and tell the owner.
- A reviewer never starts `just review`; the command stops if it is called
  inside a review.
