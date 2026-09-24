# Step 1 integration foundation

Created: 2026-09-24. Status: DONE for the foundation assignment; Step 1 remains IN PROGRESS.
Task: [Step 1](20260924-step-1-schema-extensions.task.md).
Owner: product/integration engineer. Reviewer: technical lead.
Workspace: `/Users/tzankomatev/work/sqlite-verifier-integration`.
Base: `3ada97a8`.

## Scope and interfaces

Minimal pinned development foundation, MIT license, source packaging and shared
local/CI recipes. Package `sqliteVerifier`, public library `SqliteVerifier`,
Lean `leanprover/lean4:v4.33.0`, no Lean dependencies. The formal lead owns all
Lean source modules and examples. SQLite/conformance engineer agrees on SQLite
3.51.0; Nix builds the official autoconf archive with default settings and
readline disabled. Native source hash is checked in `flake.nix`.

The setup does not implement the verifier, claim VERIFIED, or supply installable
release artifacts. Source packaging is explicitly a development snapshot.

## Evidence

- `just setup` succeeds with the already installed pinned elan toolchain. A
  clean elan-cache download was not repeated on this host.

- `nix develop --command just check` passed on aarch64-darwin: compiled the
  agreed comment-only Lean barrel, checked Lean/Lake 4.33.0, native SQLite 3.51.0
  and source identity, and checked row/value preservation plus NULL after adding
  a nullable column to a populated native table.
- `nix develop --command just package` produced a source archive; a fresh
  extraction passed the same check. This is not a verifier release.
- Both declared development shells evaluate. x86_64-linux build/execution is
  reserved for CI; this host cannot establish Linux runtime success.
- The source ID is the official upstream
  `fb2c931ae597f8d00a37574ff67aeed3eced4e5547f9120744ae4bfa8e74527b`.
  `docs/native-build-aarch64-darwin.txt` records observed native compile options.
- The formal lead approved the initial barrel; its imports will change during
  integration. No semantics or proof acceptance is implemented in this commit.
- Parent requested Python CLI support and Linux bubblewrap; both are available
  in the shell. macOS containment uses its system sandbox-exec, owned by parent.

## Handoff

Review the foundation diff and rerun `nix develop --command just check`.
Integrate formal source, parser build/tests, and CLI acceptance checks into the
shared recipes. Product runtime packaging, release CI and actual pilot evidence
remain outstanding. Lean is pinned via elan's checked-in toolchain file; initial
installation requires network. Package dependencies are pinned by `flake.lock`.

## CI follow-up — 2026-09-24

Owner: product/integration engineer. Reviewer: coordinator, then technical lead.
Base: foundation commit `2eb0b74a`.

Added a thin GitHub Actions matrix for the two declared native systems, with
full action commit pins verified against official tag refs, job timeouts,
read-only token permissions, architecture assertion, and shared Nix/just recipes.
The Linux runner must pass an unprivileged bubblewrap capability preflight;
no privileged host-policy changes or failure skips are present. Development
source archives are retained with explicit labels; no release trigger or
installable verifier claim was added. See `docs/ci.md` for source references.

Validation: actionlint 1.7.12 (including ShellCheck) passed for the workflow;
`nix develop --command just check` passed on aarch64-darwin. CI assignment is
DONE locally, pending independent review and hosted execution. Actual hosted CI execution,
including the Linux user-namespace preflight, remains for coordinator observation
after review and push; this macOS host cannot claim those results.
