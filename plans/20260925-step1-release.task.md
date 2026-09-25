# Complete Step 1 release and acceptance

Created: 2026-09-25. Status: ACTIVE.

## Required outcome

The owner-approved preservation implementation is integrated into public main,
validated on both declared platforms including installed-runtime tests, and
published as a checked release. The owner accepted the current state and requested
completion on 2026-09-25; no further design approval is required. Step 1 task,
status, roadmap, pilot review and release notes faithfully describe what shipped,
its guarantee and limitations, and the acceptance evidence. Missing historical
human effort measurements are recorded as unavailable, never invented. Owner
approval closes product acceptance; it does not fabricate timing measurements.

## Validation evidence

Full source checks and installed archive tests pass on aarch64-darwin and
x86_64-linux for the integrated implementation. Release workflow passes on the
tagged commit; both native archives and checksum assets are present and their
checksums validated. Intentional protected contract changes use existing owner
authorization without weakening branch or baseline policies. Authored Markdown
links pass. Existing local full-suite evidence for 0c5bb79e remains valid for
unchanged code; any fixes receive their appropriate bounded checks and review.

## Relevant constraints

Use jj, pinned path:./nix environments and existing CI/release jobs. Respect
resource checks; do not delete unrelated caches or data. Never overwrite a release
tag. Existing target-owned baseline enforcement intentionally rejects modified
approved sources: the owner's explicit current-state approval is the authority
for integrating this reviewed baseline through their existing audited bypass,
not permission to disable enforcement. A failed check is investigated and repaired
within scope; environmental or specification blockers require owner feedback.

Relevant files: .github/workflows/ci.yml, .github/workflows/approved-baseline.yml,
tests/baseline_ci.py, docs/ci.md, docs/release-notes.md, docs/atuin-pilot-review.md,
plans/20260924-step-1-schema-extensions.task.md and status, and the roadmap.
