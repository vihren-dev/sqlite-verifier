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
