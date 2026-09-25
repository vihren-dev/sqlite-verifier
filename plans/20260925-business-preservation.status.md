# Business preservation status

Created: 2026-09-25. Status: ACTIVE.
Task: [business-preservation.task.md](20260925-business-preservation.task.md).
Starting revision: 9a6b7ce3. Authority: owner approved the preservation-only proposal.

The repository is clean at the starting revision. Relevant interfaces and current Atuin contract inspected. Formal lead owns Lean/SQL simplification; coordinator owns docs and public acceptance checks; independent reviewer challenges recoverability, assumptions and outcome coverage. Environment remains the pinned path:./nix shell with the repository lean-toolchain. Validation pending.

2026-09-25 contract documentation checkpoint: brief revision 0.7 now makes old-model
preservation the primary workflow, without anticipated fields, target schema or
framework catalog obligations. Atuin README documents payload-only trust scope,
recoverability versus application reads, decoder domain and retained list order.
Coverage docs now describe three old-data native fixtures. Local Markdown links
pass in the pinned Nix shell (build/preservation-docs.log). All 36 Python unit
tests pass (build/preservation-unit.log); this is not yet validation of the pending
Lean example. Candidate implementation and public CLI checks remain in progress.
