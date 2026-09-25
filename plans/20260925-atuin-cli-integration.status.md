# Atuin public CLI integration

Created: 2026-09-25. Status: DONE (source CLI test unit; owner and installed acceptance remain pending).
Task: [unchanged Atuin migration](20260925-atuin-shell-migration.task.md).

Restored preserved harness 1f2379b2, merged checked formal bundle 1c3f167d,
complete native/model runner evidence 6f2ff655 and tiny environment eb6b728e.
The baseline.json map is a proposed engineering snapshot of the four approved
source modules, not human approval. Root owns the owner-review packet and
protected target-branch policy. No public bookmark or baseline policy is moved.

The bounded CLI harness exercises the exact upstream migration with complete
schema and profile, closure/artifact hashes, altered column/schema/catalog,
candidate projection omission, transitive approved-source drift and sorry.
Each CLI child has a 180-second limit. Source and installed runtime interfaces
use the same harness; installed package execution remains parent-owned.

Validation: guarded `just build` passed 23 jobs. Both the initial CLI suite and
final strengthened suite passed under a 1,500-second outer timeout and 180-second
per-case limits. The final suite requires real Lean error/axiom diagnostics for
UNVERIFIED cases and explicitly excludes timeouts. Positive input/artifact hashes
bind all four approved dependencies and exact SQL/schema/profile bytes.

Ultra independently reviewed the harness and recomputed all four baseline hashes;
accepted the positive/adversarial boundaries and sole shared-recipe hook. The
hook belongs after existing CLI tests; integrate only that line into the newer
de-duplicated justfile rather than replacing its resource/coverage changes.
Shared payload/full-runner coverage wiring belongs to the conformance engineer.
No duplicate full package or conformance batch was started. Installed archive and
both-platform integrated acceptance remain separate; owner approval is pending.
