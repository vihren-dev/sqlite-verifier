# ADR 0003 latency-first refactor

Created 2026-09-29. Status: DONE.
Status file: [status](20260929-adr3-latency-refactor.status.md).

The owner decided (2026-09-29): improving verification latency is the immediate
goal; adversarial acceptance is postponed; trust matters later; the
comparator-based preparation/checking split should serve both.

## Observable outcome

- ADR 0003 states the decision requested, current state and measured evidence at
  the top; it separates a latency milestone (trusted execution) from a deferred
  trust milestone built on the same data path; it names cheaper alternatives with
  numbers and a fallback if the data path fails.
- Deferred adversarial-acceptance detail is preserved in a linked document marked
  as deferred design, not as a current requirement.
- `docs/0003-component-research.md` marks the points where it conflicts with the
  refactored ADR.
- The latency experiments are reproducible from `experiments/adr-0003-latency/`,
  with their results and limits recorded in its README.

## Verification

- `python3 tests/docs_test.py` passes (all local links resolve).
- The experiment README's commands reproduce stage timings and export/check
  measurements on the development shell.

## Tricky points

- ADR 0004 depends on ADR 0003 for a versioned structural encoding of frontend
  results and for independent-kernel replay; both must stay.
- Comparator issue #93 (string-literal replay into an empty environment) affects
  full replay, not replay into a trusted imported base.
- lean4export normalizes metadata and `let` nondep flags; protected-declaration
  comparison must apply the same normalization.
