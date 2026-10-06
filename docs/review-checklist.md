# Review checklist

`just review` gives this checklist to an independent reviewer for one commit
(see `tools/review.py`). The reviewer is the other agent tool: Codex reviews
commits from Claude Code sessions, and Claude Code reviews commits from Codex
sessions.

## How to review

- Review only the changes of the given commit, and the definitions that these
  changes touch. Do not review unchanged code elsewhere.
- Report only violations of the conditions below. Do not report general
  preferences or advice.
- Do not change any file.
- Use **must** when the violation makes the code wrong, weakens a guarantee, or
  breaks a condition in trusted or public code. Use **should** for all other
  violations.

## Conditions

**R1. Separate "what" from "how".** A policy (an allowed list, a limit, an
exception, a reserved name) is a named definition with a docstring, not a
literal inside a mechanism. A specification states its meaning directly; an
executable version for computation is linked to it by a theorem or a test.
*Example of a violation:* the allowed axioms as a list literal inside the
traversal loop of `audit`.

**R2. Propositions in plain words.** Each new or changed proposition in the core
library or the public API (a `def` or `abbrev` of type `Prop`, a `Prop` field,
a theorem statement) has a docstring that restates it faithfully: quantifiers,
assumptions, and each case in which it requires nothing. A changed formula has a
changed restatement. See "Propositions in plain words" in `AGENTS.md`.

**R3. Proof sketches.** A new or changed library theorem that other proofs use,
or a proof longer than about 20 lines, has a proof sketch of 1-5 sentences:
the strategy and the key idea.

**R4. No compatibility paths.** The project has no users. Replaced code is
deleted and its callers are updated. No "legacy" code, no aliases kept for old
names, no fallback to an old path.

**R5. Exhaustive matches.** A `match` over `Statement`, `ExecutionError`,
`Outcome` or another type whose cases have different meanings has one case for
each constructor, without a catch-all `_` case. A new constructor must then cause
a compile error where it is not handled.

**R6. Model boundary.** The SQLite model is meant for uses beyond migration
verification, so it must not depend on that application. The model
(`Declarations`, `Model`, `Execution`, `LiteralData`, `SqlExecution` and the
lemmas about them) does not import the verification application (`Contract`,
`Library`, the demonstrations). A lemma that is only about the model belongs in
the model, not in an application file. Model docstrings speak about SQLite, not
about "approved", "candidate" or "proof" data.

**R7. SQLite rule or model restriction.** A SQLite rule is a check that SQLite
itself makes, for example "no two columns with the same name". A model
restriction excludes input that SQLite accepts but the model does not describe,
for example "no column named `rowid`". A new or changed condition in a validity
check, a supported-subset check, or `step` says which of the two it is. A model
restriction must never appear in `step` as a modeled failure: then the model
would predict an error where SQLite succeeds. It belongs in the supported-subset
check instead.

**R8. Trust-relevant change.** A change to the verification target
(`VerificationConditions` and its parts), the kernel gates (`GateCore.lean`,
`ProofChecker.lean`, `BundleChecker.lean`), the axiom policy, the export path,
`StructuralCodec.lean`, or the approval and baseline checks is reported as a
**must** finding with the text "owner review required", even if it looks
correct. This marks the change for the owner; it is not a claim of a defect.

**R9. Docstrings.** Each new class, structure, function and module has a
docstring that gives the reason for the object. Text follows "Writing style" in
`AGENTS.md`: what the code does and why, in short active sentences, with a
negative statement only to warn about a real trap.

**R10. Error messages.** A new or changed user-facing message says what failed,
where, and what the user can do next. It does not refer to internal documents
such as ADR numbers.

**R11. Tests.** A behavior change has a test that would fail without it. Tests
are deterministic, and each subprocess call in a test has a timeout.

**R12. Size and types.** A source file stays below 200 lines. Python code has
complete type hints and no `Any`.

**R13. Documentation follows the code.** Documentation that describes changed
behavior (README, `docs/`, CLI help) changes in the same commit.

## Output format

Write one line per finding, and nothing else in these lines:

```
- R<number> <must|should> <path>:<line> <one-sentence problem>. Fix: <one-sentence fix>.
```

`<path>` is relative to the repository root; `<line>` is a line in the new
version of the file. Text before or after the finding lines is allowed, for
example a short summary.

If no condition is violated, write exactly this line:

```
No findings.
```

Example:

```
- R1 must GateCore.lean:38 The allowed axioms are a literal inside the traversal of `audit`. Fix: define `allowedAxioms` with a docstring and use it in `audit`.
- R9 should migration_check/bundle.py:25 `verify_bundle` has no reason in its docstring. Fix: say why the bundle is copied before the check.
```
