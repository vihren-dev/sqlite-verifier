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

Source inspection identifies SQLx 0.9.0 with bundled SQLite 3.46.0 in the selected
Atuin revision. The pilot must account for that actual engine, not silently use
our existing 3.51.0 profile. SQLx commits the payload and metadata insert together,
then updates execution time after commit; a later error can therefore follow a
committed migration. The lead is defining the precise supported guarantee.
The additional Nix `capture` shell uses the existing flake lock. Executed version
checks report cargo 1.98.0, rustc 1.98.1 and pkg-config 0.29.2; the Rust patch
version differs from Atuin's requested 1.98.0. It supplies a real pinned-SQLx
runner harness; it will not be represented as the complete Atuin application.

The later documentation CI run `36104000145` passed Linux but exhausted the
180-second aggregate macOS kernel-gate test limit; all preceding build/parser/
native/model checks passed. The tagged release's checks remain successful.
The successful tagged macOS suite took 143.6 seconds (Linux 102.4), leaving
little headroom under the 180-second aggregate limit. Each compiler/checker
process already has a separate 30-second timeout. Root's proposed test-harness
correction raises only the aggregate limit to 360 seconds and emits each case
label immediately, so a subsequent timeout identifies its stage. Assertions
and per-process limits remain unchanged. The original suite passes locally;
the integration engineer independently accepted the aggregate-budget adjustment
and reviewed the capture-shell definition. Hosted confirmation remains pending.
The test-harness-only follow-up now applies the reviewed 360-second aggregate
budget and immediate case labels. Python compilation succeeds; all proof checks
and individual child-process timeouts are preserved.

The lead accepted all three planning/tooling/harness checkpoints and main was
advanced to `e331c3a68170`. Hosted run `36105736197` is in progress.
The real SQLx capture has now passed in the conformance workspace; its review
and integration remain pending. Root is adding separately pinned SQLite 3.46.0
grammar/tokenizer sources and an independently named native CLI, while retaining
3.51.0. The downloaded 3.46.0 amalgamation's SHA3-256 matches the official release
log; each incorporated upstream file and both archives have recorded SHA-256s.
Both parsers now build and pass the same 20 grammar-family scripts, lexical,
input-limit and UTF-8 byte-span checks. A RAISE-expression test additionally
distinguishes the actual pre-3.47 grammar from 3.51.0. Native CLI version/source-id
checks pass for both releases. Runtime packaging and loader-root collection now
include both parsers; installed archive confirmation remains pending.
The coverage collector separately inventories the 3.46.0 generated grammar and
requires its own parser-regression denominator. This adds syntax evidence only;
it does not relabel existing 3.51.0 native/model observations as 3.46.0 evidence.
