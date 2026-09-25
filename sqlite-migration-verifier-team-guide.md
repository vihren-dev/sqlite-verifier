**SQLite Verifier — Team and Working Agreement**

Version 0.2 · 24 September 2026

This guide defines how people and agents collaborate on the SQLite migration verifier. It accompanies the engineering brief and roadmap. The brief defines the product contract; the roadmap defines the current delivery priorities. This guide assigns responsibility, establishes constructive adversarial review, and explains when to involve the product owner.

**Team structure.** Begin with the product owner and three technical roles. These are responsibilities, not necessarily four full-time positions. People or agents may cover multiple roles, but a substantive change requires a qualified reviewer other than its author. Assign named occupants and substitutes when work begins. At least two technical members must be able to review consequential Lean definitions and proofs; arrange additional review if that competence is unavailable.

Work as one team delivering complete supported migration features. Specialists communicate directly about shared interfaces. The formal methods lead coordinates architecture and integration; this does not require every technical conversation to pass through the lead. Reconsider the allocation of responsibilities after each roadmap step.

**Product owner.** The human product owner owns intended user value, priorities, the meaning of successful verification, and acceptance of material limitations. They decide product tradeoffs and review the outcome of completed features and roadmap steps. The team prepares concrete alternatives and translates formal consequences into user-visible guarantees before requesting a decision.

- **Responsibilities:** define use cases and acceptance examples with the team; resolve ambiguous intent; decide proposed changes to scope, guarantees, or accepted assumptions; assess demonstrated results; approve the direction of the next roadmap step.
- **Skills:** understanding database migration workflows, evaluating examples and tradeoffs, and reviewing formal requirements with engineering support. Detailed Lean implementation knowledge is not required.
- **Soft skills:** give clear priorities, distinguish essential outcomes from preferences, expose uncertainty, make explicit decisions, and revise expectations when evidence changes. Make it safe for the team to report problems early.
- **Challenge:** ask whether the demonstrated feature solves the original problem and whether its assumptions would be realistic for a user.

**Formal methods lead and technical lead.** Own the logical architecture, Lean execution semantics, expected verification theorem, trust boundary, proof acceptance rules, and foundational proof library. Keep the parser, model, interpretation interfaces, and checker coherent. Act as team lead and take responsibility for integrating reviewed changes into the `main` branch within the approved product scope.

- **Responsibilities:** define and maintain shared formal interfaces; review assumptions and theorem dependencies; prevent vacuous verification and unintended weakening; coordinate feature ownership and cross-component changes; ensure a reviewable integrated result; consolidate product-owner questions.
- **Skills:** strong Lean 4, operational semantics, proof engineering, abstraction design, dependency analysis, and understanding the distinction between a checked theorem and correspondence with native SQLite.
- **Soft skills:** explain precise claims plainly, listen to empirical contradictions, accept correction, delegate with clear boundaries, and resolve disagreements through evidence. Avoid making personal expertise a bottleneck.
- **Challenge:** attack proposed requirements, interpretations, execution relations, and proof targets. Look for hidden premises, inconsistent starting conditions, missing outcomes, unauthorized axioms, and proofs of the wrong proposition.

**SQLite and conformance engineer.** Own fidelity to the pinned SQLite release: parser integration, environment assumptions, documentation mapping, fixture import, and native/model comparisons.

- **Responsibilities:** investigate behavior in documentation, source, and execution; preserve parsing and execution details that affect meaning; maintain independent expected observations; minimize discrepancies; track semantic coverage and exclusions; review every behavior change relevant to the modeled engine.
- **Skills:** deep SQLite knowledge, C/source and test-suite reading, SQL parsing, transactions and constraint behavior, differential and property-based testing, failure minimization, and enough Lean to inspect the modeled behavior and its assumptions.
- **Soft skills:** disciplined skepticism, patient investigation, reproducible reporting, intellectual honesty about incomplete evidence, and persistence in resolving discrepancies without defending a preferred explanation.
- **Challenge:** try to find native executions that contradict the model, including error paths, configuration differences, coercions, and transaction boundaries. Challenge claims of completeness based only on passing tests.

**Product and integration engineer.** Own the usable path from input files to an accepted or rejected migration: requirements and interpretation authoring, generated obligations, CLI, diagnostics, examples, and development/release infrastructure. Develop public library conveniences with the formal lead.

- **Responsibilities:** exercise public interfaces as a user would; integrate components; preserve the connection between supplied inputs and checked theorems; maintain acceptance examples; own local/CI parity, artifact packaging, and release workflows. Establish the repository and tooling specified in the brief: `jj` at `~/work/sqlite-verifier`, GitHub `vihren-dev/sqlite-verifier`, Nix/direnv, `just`, GitHub Actions, GitHub Releases, and MIT licensing.
- **Skills:** Lean requirements and proof authoring, developer-tool and API design, systems integration, automated testing, Nix, CI, packaging, and clear technical writing. Maintain sufficient formal expertise to act as the second Lean reviewer for changes within their competence.
- **Soft skills:** user empathy, clear error reporting, pragmatic simplification, thorough handoffs, and willingness to challenge an elegant design that is difficult to use. Distinguish demonstrated outcomes from intended behavior.
- **Challenge:** try to misuse the public interface, substitute inputs, hide data through an interpretation, or obtain success for an invalid example. Test whether a fresh user can reproduce the result and repair a rejected proof from the diagnostics.

**Constructive adversity.** Every substantive proposal or implementation has an author and a challenger. Review responsibility is explicit when the task is assigned; rotate it so each member both builds and challenges. The challenger forms their own account of the expected behavior from the approved requirement and relevant external evidence before relying on the author's explanation.

Challenge claims and artifacts respectfully. State the strongest concrete failure case you can find, including its impact and supporting evidence. Authors must address valid objections, and challengers must withdraw objections when evidence resolves them. Do not reward a number of objections or demand a defect in every review. Shared success is a useful result whose limitations are understood.

| Work under review | Challenger and attack focus |
| --- | --- |
| Requirements and interpretation examples | Formal lead and product engineer challenge hidden assumptions, missing protected data, and whether the stated property matches user intent. Bring unresolved intent to the product owner. |
| SQL parsing or translation | A non-author with SQLite competence tries ambiguous scripts, embedded semicolons, name-resolution changes, and mismatches between accepted SQL and generated meaning. |
| SQLite semantics and profile | Non-author reviewers collectively supply Lean and SQLite expertise. Try native/model counterexamples, omitted failure outcomes, and relevant settings outside the assumed environment. |
| Proof library and generated obligations | A qualified Lean reviewer tries an invalid migration, inconsistent premises, unproved assumptions, or a theorem that establishes less than the CLI promises. |
| Verification gate and integration | A non-author tries changed SQL, stale inputs, substituted requirements or interpretations, unfinished proofs, and unsupported constructs that might incorrectly receive exit `0`. |
| CLI, packaging, and release | Another member runs representative accepted and rejected examples through the packaged tool and checks diagnostics and required runtime dependencies. |

One reviewer may cover multiple areas when qualified. Add a temporary specialist when necessary. A member cannot supply independent review of their own change by switching role labels. For agents, use a separate review assignment and context focused on the original contract and evidence; another agent's agreement alone is insufficient.

Record findings in the existing task or pull request with the affected claim, evidence or reproducer, and required correction or decision. Distinguish a demonstrated defect, an unresolved question, and an optional improvement. A plausible defect in claimed guarantees blocks acceptance of the affected change until resolved. The lead resolves technical disputes through evidence and qualified review; product tradeoffs go to the product owner. An unresolved objection about correctness cannot be overridden by a vote or a preference for faster delivery.

Close an objection through a fix, evidence refuting it, explicitly unsupported behavior, or an owner-approved narrower guarantee. Reflect exclusions and changed guarantees consistently in the checker, tests, and documentation; excluded cases must return `UNSUPPORTED` where applicable. Product approval cannot establish a disputed technical claim.

An unsuccessful proof attempt is not by itself a counterexample. An accepted Lean proof is not by itself evidence that the SQLite model is faithful. Preserve these distinctions in reviews and progress reports.

**Workspaces and integration.** Members may use separate Jujutsu (`jj`) workspaces under `~/work` to avoid clashing with each other's working files. These are additional workspaces of the primary repository at `~/work/sqlite-verifier`, with working directories such as `~/work/sqlite-verifier-alice` or `~/work/sqlite-verifier-parser`. Coordinate workspace names and ownership, and do not overwrite another member's uncommitted work. The team lead integrates reviewed changes into `main`, coordinates conflict resolution with the authors, and ensures the integrated result passes the required checks.

**Working on a feature.** Keep coordination lightweight and recorded in the repository's normal task/PR records:

1. Assign one delivery owner and a challenger. Record the user outcome, relevant approved requirements, acceptance examples, affected interfaces, and known uncertainties. For uncertain investigations, choose a bounded next experiment and a point at which to reassess the approach.
2. Agree on shared interfaces needed for parallel work. Include the meaning of inputs, states, outcomes, and assumptions. Discuss proposed interface changes with affected owners before relying on them.
3. Implement a complete usable feature across the required parser, semantics, library, CLI, and conformance work. Raise discrepancies when found. Keep requirement or trust-boundary changes explicit; never quietly adjust them to make a proof or test pass.
4. Run the adversarial review. Give the challenger exact revisions, commands, examples, assumptions, and evidence. Correct substantive findings and have the challenger check the resolution.
5. Hand reviewed changes to the team lead for integration into `main` and verification through the relevant shared local/CI checks. Record the supported behavior, limitations, and remaining issues. Provide a concrete demonstration for product review. A completed roadmap step also requires a roadmap review and update.

Routine refactors, fixes, and implementation choices within the approved scope are team decisions. Technical review and product feedback serve different purposes; neither substitutes for the other.

**Additional working rules for agents.** Apply the same responsibilities and review standards to agent contributions:

- On joining or resuming work, read the current brief, roadmap, this guide, and the active task and decision records. Resolve conflicts against recorded owner decisions; ask when intent remains ambiguous.
- Give each assignment a goal, scope, base revision, acceptance evidence, and named reviewer. A temporary worker may implement a bounded part of a feature; the delivery owner remains accountable for its readiness for integration by the team lead.
- Follow the shared workspace rules above. Identify the workspace and exact revision being handed off and reviewed.
- Keep decisions and findings in shared durable project records. A handoff states what changed, what was actually checked, unresolved concerns, and the next action. Private conversation history is insufficient for another agent to resume the work.
- Treat approved requirements and trust policy as constraints. Propose changes separately and route them to the appropriate reviewers or product owner. Local success does not authorize weakening the acceptance gate.
- Keep expected native observations independent of the formal model. Reviewers should inspect original sources and reproduce relevant behavior, including failures, rather than only summarizing the author's report.
- Escalate repeated failed approaches when new evidence changes feasibility or direction. Do not hide stalled work behind further task decomposition, repeated proof retries, or optimistic completion claims.

**When to sync with the product owner.** Syncs are driven by a need for input. There is no required calendar cadence. At feature completion, after an unexpected finding, and when reassessing a failed approach, ask: “Do we have the intent, priorities, and authority needed to choose the next useful action?” If not, request a sync promptly.

Any member may identify the need and request a sync. The technical lead normally consolidates related questions and sends the ping; this must not suppress or indefinitely delay an unresolved concern. Establish an agreed contact channel at project setup; until another is chosen, use the current project conversation. Agents without access to that channel surface the request through the coordinating agent and mark it as awaiting owner input.

| Trigger | Input to request |
| --- | --- |
| A feature is technically complete | Present a working example and limitations; ask whether the result meets the intended need and what the new evidence implies for priorities. Bundle related small tasks into one feature review. |
| A roadmap step is complete | Review the shipped product and evidence, update the roadmap, and choose the next commitment. |
| Unexpected difficulty changes feasibility, likely effort, or value | Explain the finding and investigation so far; ask whether to narrow scope, change approach, defer the feature, or invest further. Routine obstacles resolved within the plan need no sync. |
| Requirements, assumptions, or guarantees need a decision | Present the concrete ambiguity or tradeoff and its effect on users. Ask for the intended meaning or acceptable limitation before relying on the change. |
| Work appears to be drifting from the intended outcome | Show the mismatch between current work and the agreed user outcome; recommend a correction or stopping point. |
| A discovered defect undermines a claimed or shipped guarantee | Report the affected guarantee and examples promptly, take corrective action within existing authority, and ask for any needed scope or release decision. |
| An unresolved disagreement needs a product tradeoff | Summarize the competing conclusions and evidence; ask for the product decision while keeping unresolved technical claims explicit. |

A completion sync presents reviewable work. Do the engineering and relevant review first; do not ask the product owner to approve an abstract promise when a concrete result can be prepared. If no new decision is needed and the next task is already authorized, send the completion update and continue that work.

Keep each ping short and actionable:

> **Input needed:** the decision or feedback requested, and why it is needed now.  
> **Evidence:** the result or obstacle, with a demonstration, reproducer, or relevant artifact.  
> **Options:** the practical alternatives, consequences, and team's recommendation; state material disagreement.  
> **Work status:** what is blocked, what can continue, and any actual decision deadline or cost of delay.

Do not ask the owner to debug implementation details that the team can resolve. Investigate enough to make a useful request, without concealing a material problem while attempting open-ended fixes. Consolidate related questions and avoid repeated pings without new information; follow up when impact or urgency changes or as previously agreed.

While awaiting a response, continue already-authorized work that does not depend on the decision. Pause only affected commitments and keep any exploratory alternatives clearly provisional. Silence is not approval of changed guarantees, assumptions, scope, or resource commitments. Record the owner's answer and its consequences so every member resumes from the same decision.

**Maintaining this agreement.** At each roadmap review, examine where collaboration failed: late integration, weak challenges, repeated misunderstandings, missing expertise, excessive interruptions, or problems escalated too late. Adjust role allocation and working rules accordingly. Keep the shared records sufficient for another person or agent to understand the current goal, accepted decisions, evidence, and next action.

## Development resources

The integration engineer owns development storage and release-resource checks.
Use `python3 tools/check_resources.py` before environment setup or expensive work.
It requires 10 GiB free on the actual workspace-output, temporary, elan/Cargo-cache and
Nix-store filesystems. It rejects symlinks, unexpected files and more than 1 MiB
of environment inputs. Failure stops the expensive operation with a diagnostic;
no check deletes anything. Bootstrap Python 3 is required before environment
entry; the pinned shell supplies Python for subsequent commands.

The complete environment input is `nix/flake.nix` plus `nix/flake.lock`. Always
use explicit `path:./nix` references; `./nix` alone can discover a parent Git
repository, while a root path flake can copy a whole non-Git workspace. Never put
build outputs, archives, workspace metadata or application data in `nix/`.

Enter `nix develop path:./nix#capture` once for full checks, Rust capture or a batch
of related work. `nix develop path:./nix` suffices for focused non-Rust checks.
Inside the shell, run the relevant recipe directly. `just check` and
`just atuin-native` require the capture shell and do not enter Nix again.
Keep artifacts in `dist/`, `build/` and `.lake/`, outside the environment boundary.
The real snapshot regression is `python3 tests/environment_snapshot_test.py`;
it uses only tiny explicit path-flake metadata operations and no builds.

Routine work runs focused checks. Integration checkpoints run the complete
verification suite on both supported platforms. Packaging/runtime changes and
release candidates also build and test installed archives. Retain current useful
local evidence; after integration, identify superseded task-owned generated
outputs by exact path and ask before deleting them. The integration engineer
proposes retention/cleanup; the owner authorizes the concrete deletion scope.

The previously identified unreferenced project snapshots require the owner's
separate explicit cleanup approval. This policy grants no blanket Nix garbage
collection, cache purging, user-database deletion or volume cleanup. A low-space
failure requires a targeted request, not an automatic cleanup workaround.
