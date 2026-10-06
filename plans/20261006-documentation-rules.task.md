# Checked public documentation rules

Created 2026-10-06. Status: IN PROGRESS.
Status file: [status](20261006-documentation-rules.status.md).
Source: the rules portion of [issue #26](https://github.com/vihren-dev/sqlite-verifier/issues/26).

## Observable behavior when done

`AGENTS.md` requires user-directed Verso docstrings for public Lean declarations
and their fields. A changed public declaration has its docstring updated in the
same commit. Checked names and examples are verified when Lean compiles them.
The rule states the limitation on forward references within one file: a checked
reference follows the declaration it names, or appears in a module walkthrough
at the end of the file. Plain code spans do not count as checked references.

The existing plain-words rules for propositions remain in force. They still
cover quantifiers, assumptions, each conjunct or case, and cases in which a
formula requires nothing. Names in these statements use checked references.

## Acceptance checks

Review compares the new rules with public issue #26 and its plain-words
comment, and checks that the existing proposition rules retain their meaning.
The forward-reference limitation and same-commit requirement are explicit.
This task changes policy only; the API reference and existing declaration
documentation remain separate work under #26.

## Relevant files and constraints

`AGENTS.md` contains the writing style and plain-words rules. The new rules
extend them. Lean's Verso option checks references during compilation; a
custom documentation checker is unnecessary. The full documentation work
will pin doc-gen4 to the chosen Lean toolchain in a separate task.
