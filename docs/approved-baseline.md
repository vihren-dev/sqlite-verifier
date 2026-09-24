# Protecting approved requirements

The engineering examples carry CLI-compatible `baseline.json` files in each
`approved/` directory. They record the exact SHA-256 of Requirements,
Interpretation and every local Lean helper. These initial maps describe synthetic
engineering examples; they do not represent a pilot's approval of application
requirements. The approved library and verifier implementation are separate
trusted code and require their own review.

Pass the appropriate protected file to `migration-check verify
--approved-baseline PATH`. The driver compares the complete compiled approved
source closure, including added, removed and changed dependencies, before accepting
a proof. An `--artifacts` `inputs.json` export is inspectable evidence, not an
approval: copying it over a baseline does not authorize new requirements.

## CI boundary

The `Approved baseline` workflow exposes the check **Protected approved baseline**.
It uses `pull_request_target`, read-only repository permission, and checks out the
exact target-branch commit. It fetches the candidate commit as Git objects only.
The target branch's Python checker reads those blobs; it never checks out candidate
files, imports candidate Python, runs candidate Lean, enters its Nix environment,
or loads its build configuration. Full lowercase commit hashes are validated and
passed as subprocess arguments. A PR cannot change its checker or manifest to
approve itself.

The target manifests pin the exact set of `.lean` files under both approved
example directories. This conservatively includes unused helpers as well as the
actual import closure; all application dependencies should live within the
reviewed approved tree. The separate driver check uses the exact compiled closure.
Any changed baseline, changed source, added source, removed source or source
symlink fails CI. A newly introduced workflow cannot enforce itself before it
exists on the target branch; bootstrap requires direct owner review.

## Deliberate changes

A requirements change is a separate human review decision, not a proof repair.
The owner reviews the semantic changes and all affected local/library dependencies,
checks that assumptions have not silently excluded states or failures, and reviews
the resulting hashes alongside the source diff. An intentionally updated baseline
and its source changes may land together only after explicit owner approval and a
recorded maintainer bypass of the expected failing drift check. There is no
automatic baseline refresh or approval inferred from compilation or successful
proofs. Ordinary migration-only PRs must pass without a bypass.

GitHub may disable `pull_request_target` through workflow event policy on public
repositories. Confirm this narrowly scoped, data-only workflow is allowed before
calling the check enforced; see GitHub
[workflow execution protections](https://github.blog/changelog/2026-09-17-workflow-execution-protections-in-github-actions-generally-available/)
and [safe target-event usage](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target).

Proposed repository rules, **not configured by these files**:

- Require PRs, current code-owner approval, and dismiss stale approvals after pushes.
- Require `Protected approved baseline` plus both platform build/check jobs,
  and require branches to be up to date before merging. Retargeted PRs rerun the
  baseline workflow; a stale target-branch baseline must not authorize a merge.
- Restrict bypass to designated maintainers; record why the baseline change was
  authorized. Do not grant a general automation-token bypass.
- Protect `.github/CODEOWNERS`, workflows, the baseline checker, trusted compiler,
  parser, proof gate, formal library and toolchain pins under `@tzanko-matev`.

CODEOWNERS requests reviews; it does not enforce them without repository rules.
Human owners must also review changes to the check's target-branch implementation.
