"""Mutants of triggers (ADR 0018, slice 5).

The task of slice 5 lists the changes that the conformance suite must notice. Each mutant is
one text change in a copy of the model, which `conformance.resolve_mutants.measure` builds and
runs against its target case of `conformance.authored_triggers`.
"""

from conformance.resolve_mutants import SQLITE

RULES = SQLITE + "Resolution/TriggerRules.lean"
"""The trigger programs of a write, the newest trigger first."""
PROGRAM = SQLITE + "Resolution/TriggerProgram.lean"
"""The events of a program and the writes that fire them."""
RUN = SQLITE + "TriggerRun.lean"
"""The run of the programs of a row."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "oldest_first": (RULES,
        "  | first :: rest => if program.trigger ≥ first.trigger then program :: first :: rest else first :: insertNewest program rest",
        "  | first :: rest => if program.trigger ≤ first.trigger then program :: first :: rest else first :: insertNewest program rest"),
    "when_null_passes": (RUN,
        "  if !(program.condition.all fun condition => Resolved.truthy (condition.eval (.plain frame.clock) cells)) then",
        "  if !(program.condition.all fun condition => !Resolved.falsy (condition.eval (.plain frame.clock) cells)) then"),
    "ignore_runs_later": (RUN,
        "  (frame.fired table time event).foldlM (fun (state, ended) program => if ended then pure (state, true)",
        "  (frame.fired table time event).foldlM (fun (state, _) program => if false then pure (state, true)"),
    "update_of_every_update": (PROGRAM,
        "  | .update (some listed), .update set => (set.getD []).any listed.contains",
        "  | .update (some _), .update _ => true"),
    "fires_itself": (RUN,
        "  if !frame.recursive && frame.running.contains program.trigger then return (state, false)",
        "  if false then return (state, false)"),
}
"""Each mutant: the file under `packages/`, the exact text it changes, and the replacement.
The names follow the list in the task of slice 5: triggers that run oldest first, `WHEN` that a
NULL passes, `RAISE(IGNORE)` in an `AFTER` trigger that still runs the later triggers of the row,
`UPDATE OF` that runs for every `UPDATE`, and a trigger that fires itself."""

TARGETS: dict[str, tuple[str, ...]] = {
    "oldest_first": ("order",),
    "when_null_passes": ("when",),
    "ignore_runs_later": ("ignore-after",),
    "update_of_every_update": ("update-of",),
    "fires_itself": ("not-recursive",),
}
"""The authored case of `conformance.authored_triggers` that each mutant changes."""

GUARDS: dict[str, str] = {
    "oldest_first": "rule:insertNewest",
    "when_null_passes": "rule:runProgram",
    "ignore_runs_later": "rule:runPrograms",
    "update_of_every_update": "rule:TriggerEvent.fires",
    "fires_itself": "rule:runProgram",
}
"""What each mutant guards: `rule:` and the Lean declaration of its file that the mutant
changes. `conformance.mutant_guards` checks every entry."""
