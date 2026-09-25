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

## Real runner capture checkpoint

Conformance implemented `conformance/atuin_capture`; repeat commands are in
`docs/atuin-capture.md`. Actual SQLx 0.9.0 executes the preceding six migrations
and unchanged shell migration. All 162 resolved registry dependencies match
upstream lock identities. Native SQLite 3.46.0 source96c92aba, compile options
and effective PRAGMAs are captured; no different engine was substituted.

Each complete schema inventory contains eight objects: history and bookkeeping
tables, three explicit indexes and three constraint indexes. Metadata contains
six/seven successful SHA-384-bound migration rows. JSON retains implicit-index
NULL SQL entries; DDL recreates them via constraints. The actual SQLx harness is
explicitly distinguished from the complete Atuin executable and its background
WAL housekeeping. Original SQL and upstream license are retained.

Nix capture build passed in 21.10s; repeat native regression passed in 0.024s
under a 40s timeout. It checks complete schemas, dependency/migration hashes,
metadata checksums/success and refusal to overwrite an existing database.
Independent source/evidence review was requested from the technical lead.
Runner failure/adversarial tests remain subsequent work. No model extension,
invocation certificate, owner acceptance or DONE is claimed.

## Native runner adversarial checkpoint

Added a bounded real-SQLx adversarial executable and eight scenarios, with
receipts and documented fault boundaries. Payload/metadata-insert failures
roll back; timing-update failure retains committed ADD and metadata time=-1.
Dirty/checksum/unknown-version checks reject unchanged, and already-applied
target succeeds unchanged. Each preserves the exact old storage/rowids of a
native-valid witness including two NULL primary keys, signed-rowid extremes,
mixed storage classes and embedded-NUL text. Native integrity checks pass.
Fault-trigger schemas are explicitly outside pilot admission. Cache-clear
failure remains source-based evidence only. Shared native capture helpers
avoid duplicating the selected connection profile.

Locked offline build passed in 2.34s. Both capture and adversarial regression
suites passed under a 45-second outer timeout; individual native subprocesses
also have 30-second limits. No new formal/native correspondence claim is made.

Root's post-close review found a material capture correction: actual
optimize-on-close creates sqlite_stat1/stat4 even for the empty fixture. The
earlier eight-object during-run export was incomplete as a persisted baseline.
Following the lead's boundary decision, capture now closes after six migrations,
reopens the actual ten-object baseline, executes the target, and records both
invocation result and post-close state. Full statistics rows are retained as
observations. Native runtime limits are queried read-only through SQLx's locked
handle. Export bytes and compile options are checked against fresh reproduction.
Adversarial runs begin with the persisted statistics-bearing baseline and check
history after closing; no statistics object is silently removed.
Final revised offline build passed in 1.96s; both native regression suites passed
in 0.205s, including all eight adversarial scenarios. Tests reject stale schema
exports or a mismatched compiler configuration rather than silently accepting
a different native profile.

Root integrates both reviewed parser checkpoints and the persisted-runner capture.
The complete local coverage refresh passed, including both separate grammar
inventories; native capture integration and hosted platform checks follow.
The integrated checkout independently rebuilt the locked SQLx harness offline
in 14.99 seconds, reusing the conformance workspace's downloaded Cargo registry.
Both complete capture and eight-scenario native runner tests passed in 0.234s.
The `atuin-native` shared entry point and both-platform CI step reproduce the
locked runner and retain fresh adversarial receipts. These are finite native
observations; they are not yet a proof/model comparison or pilot acceptance.
The exact shared command passed both native suites (0.263s); actionlint and
shellcheck accepted the workflow. Earlier run `36105736197` has passed Linux;
macOS remains in progress. No hosted Atuin result is claimed yet.

The lead approved separating only SQLite's `COMPILER=` option for cross-platform
reproduction: upstream sqlite3.c constructs it solely from compiler identity
macros. The actual compiler string is retained in raw options and its own field;
all other compile flags and runtime limits remain exact comparisons. Fresh
platform capture is retained at build/atuin-capture.json for CI inspection.

## Independent payload native/model comparisons

Merged immutable frontend8e35b418 and formal66a8e381 with the captured native
profile. Three independently specified stored-value fixtures (empty, singleton,
three rows) pass real SQLx before/after/post-close comparisons and production
3.46 parser/translation into Lean. Kernel assertions establish schema validity,
concrete row validity, model Conforms, successful payload result, exact expected
NULL-extended history and unchanged other modeled tables. A false empty expected
result is rejected. The full ten-object captured schema and native profile remain
bound. Non-history model rows are explicitly abstracted empty in this payload
unit; full SQLx readiness/bookkeeping/statistics relation is NOT_YET_COMPARED.

Normal standalone test passed in11.883s; existing capture/adversarial tests passed
in0.216s. Native subprocesses have30s limits, Lean checks45s, suite180s. Reports
and actual generated proofs are retained under build/atuin-model-payload*. Root
owns shared command/coverage integration. Full runner relation comparison follows
the independently provided runner8ca23cd5 interface; no owner acceptance implied.
The Ultra lead accepted parser, coverage and complete capture checkpoints through
`9e65f66a`. Root merged them, preserving both progress records; CI retains the
fresh complete capture alongside runner receipts. Formal/profile integration
remains active in separate workspaces.
The merged shared native entry point passed both suites in 0.227s after a
2.22-second incremental build; workflow actionlint/shellcheck passed again.
