# Protected engineering baselines

Created: 2026-09-24. Status: DONE for local implementation; remote enforcement remains pending.
Task: [Step 1](20260924-step-1-schema-extensions.task.md).
Owner: integration engineer. Coordinator owns remote repository settings.

The component protects approved source/dependency hashes for the engineering
examples. It includes CLI-compatible manifests, a target-branch-owned static Git
object check, CODEOWNERS and deliberate human review/bypass documentation.
The baseline workflow does not execute candidate code. No branch rules are changed
remotely and the synthetic examples are not presented as human pilot approval.

Checks cover changed transitive helpers, self-modified baselines, added/removed
sources, symlinks, malicious candidate checker code and invalid commit identities.
`timeout 20 python3 -m unittest tests.test_baseline_ci` passed (0.890 seconds).
Actionlint 1.7.12 with ShellCheck 0.11.0 passed for the new workflow. Both real
example manifests exactly match their two approved Lean source hashes.
The workflow uses the already verified actions/checkout v6 commit pin.

Official GitHub documentation confirms static inspection is suitable for the target
event, while the September 17 workflow event-policy change may require an explicit
allowance. No remote activation or branch protection is claimed. The proposed
required check is `Protected approved baseline`; intentional changes require owner
review and a recorded maintainer bypass, never self-approval by a PR manifest.

Independent conformance review accepted the source, workflow and documentation;
its bounded reproduction passed in 0.899 seconds. The real manifests also passed
the checker against Git snapshot `65900f28` (using the colocated primary Git
repository because the separate jj workspace has no `.git`).

Read-only GitHub API inspection on September 24 returned Actions enabled and
`allowed_actions: all`; listing repository policies with `has_parents=true`
returned `total_count: 0`. No configured or inherited event restriction was
observed. The documented default starts in evaluation mode before November 2
enforcement; the coordinator received an exact workflow-scoped policy proposal.
No remote configuration was changed by this component.
