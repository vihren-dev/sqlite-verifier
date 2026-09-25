# Atuin shell migration status

Created: 2026-09-25. Status: IN PROGRESS — not DONE.
Task: [unchanged Atuin migration](20260925-atuin-shell-migration.task.md).
Parent: [Step 1](20260924-step-1-schema-extensions.task.md).

## Accepted scope and current evidence

The owner selected Atuin and authorized the necessary support extension. This
resolves the prior project/scope decision; routine work proceeds autonomously.
Target revision `5b10eb09c664d316b7384210399b02e6127f4027`, migration
`crates/atuin-client/migrations/20260709214605_shell.sql`.
The proposed requirement preserves physical rowid and every old stored history
field while adding nullable `shell TEXT`. Final concrete logical review remains.

Starting verifier revision: `669bb0e1a5b800ddd7e02b892f87af932b1ef548`.
Published `v0.1.0-rc.1` at `c840b0434186` has passed both native platform jobs and
installed smoke tests. Toolchain remains Lean 4.33.0 and SQLite 3.51.0 via Nix.

Prior scratch research replayed six application SQL files and admitted the target
ADD statement, but rejected the complete application table definition's UNIQUE
constraint. That reconstruction omitted SQLx bookkeeping. It is diagnostic
research only; the actual complete runner capture remains to be established.

## Responsibilities and active work

- Ultra technical lead: formal architecture, arbitrary-data proofs and final
  integration acceptance in the formal workspace.
- Medium conformance reviewer: pinned upstream/SQLx evidence, real capture,
  independent native/model and adversarial checks in the parser workspace.
- Medium integration engineer: reusable CST admission, generated bindings,
  execution-profile and CLI integration in the integration workspace.
- Root coordinator: task/status records, integration, public artifacts and
  owner communication. No implementation precedes this task/status checkpoint.

Relevant code is identified in the task. Initial investigation must resolve the
exact runner/dependency profile, faithful baseline representation and transaction
boundary before implementing affected interfaces. No original requirements are
waived, and no new semantics are claimed by this planning checkpoint.

The later documentation CI run `36104000145` passed Linux but exhausted the
180-second aggregate macOS kernel-gate test limit; all preceding build/parser/
native/model checks passed. The tagged release's checks remain successful.
Root is investigating this bounded-test failure; no cause or fix is yet claimed.
