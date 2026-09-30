# Bounded generation and proven regressions (W3/W4)

`just test` runs two Hypothesis RuleBasedStateMachine modes at seed 4004,
20 examples and at most eight actions per example. Each example checks a DDL
program and a keyed DML program: the production frontend conservatively excludes
CREATE mixed with a baseline containing keys. Every rendered program must decode
to the original structural constructors. SQLite records the trace; compiled
`classifyCase` remains the sole agreement authority. Atomic errors, successful
rollback, and ADD row preservation also run as native properties.

The schema varies across INTEGER, NUMERIC, REAL, TEXT and BLOB affinities with
values inside each admitted domain. UPDATE writes a different value; ADD acts on
a populated table. Error-seeking programs end with a duplicate-key attempt so
uniqueness is exercised even when the random action mix does not choose it.
Unsupported conversion probes are recorded natively in `boundaries.jsonl` with
their verdicts; an unsupported outcome is not a generator failure.

The value strategy favors NULL, empty TEXT/BLOB, numeric-looking text, signed
integer limits and byte/control-character cases. Separate native boundary probes
retain unsupported integer-affinity conversions, REAL literals (including signed
zero and 1e20), and 2^63; none count as agreement. A 2000-column fixture exercises
the actual column-limit error. Error-seeking actions cover duplicate/missing
objects, transaction-state errors, NOT NULL and uniqueness failures.

`just conformance-generate` writes the bounded run's cases and report under
`build/generated`. `just conformance-mutations` compiles isolated copies of the
production definitions and classifies those exact generated cases against four
mutants. The [fixed-seed evidence](../reports/20260929-adr4-generator-mutations.json)
kills ignored UPDATE (7 cases), missing ADD NULL padding (16), ineffective
ROLLBACK (7), and disabled uniqueness (20). Production semantics are untouched;
these tests measure detection ability, not discovered bugs.

The [bounded run](../reports/20260929-adr4-generator-review.json) has 88 agreements
and 44 unsupported probes. The [strengthened long run](../reports/20260929-adr4-generator-review-long.json) has 2,088 agreements and
1,044 unsupported probes, with no disagreements. Counts are executed instances,
not distinct programs or requirement coverage. The previous 2,032-agreement
run used a narrow BLOB-only generator and is historical infrastructure evidence.
`just conformance-long` explicitly selects 500 examples per
mode and 25 actions, under a 600-second command timeout. Neither long generation
nor upstream re-extraction gates ordinary development. Hypothesis and its seed
are pinned by the Nix environment. The transaction/DML profiling prerequisite is
recorded in [the task status](../plans/20260929-adr4-w3-w4-generation.status.md):
redundant schema-parser startup was removed before scheduling long runs.

On failure, Hypothesis prints the shrunk action sequence and exact fixture.
`conformance.regressions.minimize` then deletes statements while preserving the
classifier's verdict and first divergent position. Classify every confirmed
mismatch as model bug, harness bug, documentation gap, or deliberately modeled
engine quirk. Fix the cause; never edit a recorded native trace to gain agreement.
`freeze` requires a classification and resolution, reacquires native truth,
checks compiled agreement, and runs a kernel proof plus axiom audit before
writing immutable case/proof/mismatch files. Existing evidence cannot be overwritten.

The retained [fault-injection regression](../conformance/regressions/injected-literal-corruption/mismatch.json)
changes only the model's INSERT payload. Hypothesis shrinks it to one INSERT;
restoring the payload yields the committed tier-two proof. This demonstrates the
workflow and is explicitly **not a discovered production bug**. Tests recheck both
fresh native evidence and the saved kernel proof. Generated-run counts remain
separate from proven case counts; finite testing does not prove refinement.
