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

## Replaced code

The project has no users. When code is replaced, update all callers and delete
the old code. Do not keep compatibility paths, and do not mark code as "legacy".
Do not keep aliases for replaced names or fall back to a replaced path.

Review this rule again before the first public release, when users and
compatibility matter. Historical evidence and the readers needed to replay it
are retained; they are not replaced implementation paths.

## Lean maintenance

Until the project has users, follow each stable Lean release. Upgrade within
two weeks after a stable release, in its own change, with no other work in it.
Do not adopt release candidates. If a Lean dependency (lean4export, comparator,
doc-gen4) has no tag for the new version, try to build its latest tag under the
new version; if that fails, record it in the upgrade issue and wait for the
dependency. Do not downgrade the toolchain automatically.

This policy covers the Lean toolchain and the Lean dependencies built with it.
It excludes the SQLite versions in the execution profiles: those versions
define verification semantics and change only as product decisions.

Review this policy when the project gets its first users. Upgrades must then
also consider compatibility of user proofs.

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
- Exit code 0: no "must" findings. Fix "should" findings, or reject or defer
  them with a reason.
- Exit code 1: fix each "must" finding in a `refactor:` commit before the next
  feature commit, and review that commit too. After two review rounds with new
  "must" findings, stop and report to the owner.
- Record the outcome of every finding with
  `just review-resolve FINDING-ID fixed`, or `rejected "REASON"`, or
  `deferred "REASON"`. `just review` prints the finding ids. Reject a finding
  when it is wrong, and say why.
- `just review` and `just review-resolve` add lines to `reviews/log.jsonl`.
  Commit the log with your next commit. Do not edit or delete log lines.
- The owner uses `just review-stats` to find conditions that never fire, are
  mostly rejected, or that nobody acts on, and removes or rewrites them.
- Exit code 2: the command cannot choose a reviewer or revision; follow its
  message (for example, set `REVIEWER=claude` or `REVIEWER=codex`).
- Exit code 3: the reviewer failed or gave no recognizable result. Run the
  review once more; if it fails again, record it and tell the owner.
- A reviewer never starts `just review`; the command stops if it is called
  inside a review.
