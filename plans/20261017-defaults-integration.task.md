# Literal defaults in the ADR 0012 stack, slice 6e1 of ADR 0012

Created 2026-10-17. Status: open.
Specification: [ADR 0012](../docs/adr-0012-query-semantics.md), "Amendment 5", "The clock
(slice 6e)", owner decision 9 of 2026-10-17; draft #130 and its task
(`plans/20261012-constant-column-defaults.task.md` on `tasks/constant-column-defaults`),
which this slice brings into the stack. Related: slice 6e2 (the clock), which needs
column defaults for `CURRENT_TIMESTAMP`.

## Pull requests

- **Pull request A (subject):** a merge of `tasks/constant-column-defaults` (#130) into the
  stack after #149, with the conflicts resolved and the interactions with slices 5a to 6d
  made explicit. No change under `judge/` or `integrity/` beyond what #130 has.
- **Pull request B (judge, owner approval), only if cases newly agree:** they are added to
  `mustAgree`.

## Outcome

1. **#130's outcome holds in the stack.** Everything that #130's task states as true
   (literal defaults of added columns, NOT NULL with a default, existing rows that read
   the default after affinity, omitted INSERT values that the default supplies, the
   source spelling of defaults, the invoice example) is true on top of slices 5a to 6d.
2. **The stack's outcomes keep holding.** Every outcome of slices 5a to 6d holds with
   defaults: keys and rowid aliases, UPSERT and conflict algorithms, queries without FROM,
   the JSON functions and their failure rules, and `json_each`.
3. **One model.** There is one default model and one value conversion (`storeValue`); no
   compatibility path or second implementation.
4. **Verification target.** `Contract.lean` does not change; every write keeps `Conforms`.
5. **Evidence.** The checks of #130 and of the stack pass; the verdict counts of the
   claimed corpora do not go down.

## Tests

- `just test-full`, `just test-nix` and `just test-scheduled` (mutants) pass on the merge.
- #130's model, frontend, codec, gate and example tests pass in the stack.
- The authored cases of slices 5a to 6d keep agreeing, with their kernel proofs.
- Cases of the stack that combine its forms with a default (an omitted value with a
  rowid alias, a key, `ON CONFLICT` and `INSERT OR`) agree natively, or are refused as a
  model restriction where the model does not describe them.

## Key points for the implementer

- **Conflicts.** A trial merge conflicts in 16 files (21 regions), among them
  `Resolution/Context.lean`, `Definitions.lean`, `Writes.lean`, `SqlExecution.lean`,
  `Execution.lean`, `SchemaExtension.lean`, and the conformance `Case.lean`,
  `Outputs.lean` and `Predict.lean`. Semantic interactions do not show as conflicts:
  check every statement form that slices 5a to 6d added against omitted values.
- **#130's open items.** #130 is a draft with open owner review items (the column
  representation, the codec, verification behavior and its example's contract). The
  integration keeps its design and does not decide them; the pull request lists them.
- **Restrictions.** Where a stack form meets a default in a way that neither side models,
  the form is a model restriction with a registry entry; it is never an invented SQLite
  error.
