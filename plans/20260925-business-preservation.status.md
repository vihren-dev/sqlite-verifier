# Business preservation status

Created: 2026-09-25. Status: DONE (implementation and local validation).
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

2026-09-25 completed implementation: the protected old History excludes shell;
requirements use the new small LogicalContract.preservation helper, with equality,
no prescribed next schema and successful execution required. General contract and
failure primitives remain unchanged. The supplied SQL is the single upstream ALTER
payload. The application schema omits the trusted framework catalog. Deleted six
obsolete Lean files; the example is now 491 Lean lines across 11 files. Candidate
proofs establish complete old-field recovery for arbitrary admitted databases;
empty and populated witnesses remain, and protected hashes were updated.

Independent conformance engineer reviewed the exact final proof, starting-state
admission, decoder coverage, result-only reader, all-outcome argument and README;
no blocking finding. Native fixtures intentionally include storage outside the
formal decoder domain and are documented as finite additional storage evidence,
not proof witnesses or native-engine refinement. No application source import or
framework integration was added.

Validation: lead public CLI VERIFIED the exact one-statement payload with the
protected baseline (artifacts build/atuin-preservation). Coordinator then ran the
full `just check` in one persistent `nix develop path:./nix` environment on
aarch64-darwin with pinned Lean 4.33.0 and SQLite 3.51.0/3.46.0: exit 0,
build/preservation-check.log and build/preservation-check.exit. The batch includes
25-job library/checker build, pinned smoke, fresh grammar/native/model coverage,
three Atuin native cases, environment-source identity, parser reuse, documentation,
schema generation, adversarial kernel gate, real compilation isolation, ordinary
CLI, Atuin CLI, seven coverage tests and 36 Python unit tests.

Atuin CLI verifies both shell and a differently named nullable added column with
identical approved hashes. Eleven negative cases reject stale candidate proofs,
changed protected inputs, unsupported default semantics, dropped histories, erased
commands, missing representation conditions and unfinished proofs. Rejection is
checked to be a real diagnostic, never a timeout. These negative attempts are not
reported as formal refutations.

No environment blockers. No archive rebuild or cache cleanup was needed; packaging
was unchanged. No new Linux-hosted run or publication is claimed. The implemented
guarantee remains recoverability of the approved old business information under
the modeled execution assumptions, not new-feature or application-query fidelity.
