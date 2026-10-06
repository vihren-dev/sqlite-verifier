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
