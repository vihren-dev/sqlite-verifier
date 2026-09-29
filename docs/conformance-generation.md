# Bounded generation and proven regressions (W3/W4)

`just test` runs two Hypothesis RuleBasedStateMachine modes at seed 4004,
20 examples and at most eight actions per example. Each example checks a DDL
program and a keyed DML program: the production frontend conservatively excludes
CREATE mixed with a baseline containing keys. Every rendered program must decode
to the original structural constructors. SQLite records the trace; compiled
`classifyCase` remains the sole agreement authority. Atomic errors, successful
rollback, and ADD row preservation also run as native properties.

The value strategy favors NULL, empty TEXT/BLOB, numeric-looking text, signed
integer limits and byte/control-character cases. Separate native boundary probes
retain unsupported integer-affinity conversions, REAL literals (including signed
zero and 1e20), and 2^63; none count as agreement. A 2000-column fixture exercises
the actual column-limit error. Error-seeking actions cover duplicate/missing
objects, transaction-state errors, NOT NULL and uniqueness failures.

`just conformance-generate` writes the bounded run's cases and report under
`build/generated`. `just conformance-long` explicitly selects 500 examples per
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
