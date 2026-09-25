# SQL-only core cleanup status

Created: 2026-09-25. Status: IN PROGRESS.

Task: [sql-only-core.task.md](20260925-sql-only-core.task.md).
Authority: owner's explicit SQL-file universal-interface correction, 2026-09-25.
Starting revision: d6c46ef1. Lean toolchain is pinned by lean-toolchain; the Nix
environment stays isolated in nix/. No framework or application execution is a
product requirement. Owner review of application meaning remains separate from
mechanical validation.

Progress: audited the profile-to-execution coupling; preparing source-backed SQL
example and removal of SQLx semantics, capture infrastructure and documentation.
Validation: pending implementation. No claim of equivalence or passing tests yet.

2026-09-25 environment and scope cleanup: removed the Rust/Cargo capture shell,
capture recipes and runner-specific CI artifacts; retained pinned SQLite tools,
small Nix source boundary and resource checks. Brief/roadmap now state the SQL-only
boundary. Prior runner task is explicitly superseded; historical capture/review
documentation points to the current example instead of asserting obsolete results.
Seven resource/CI-routing regressions pass. Real Nix source regression passes in
Git-parent and non-Git directories: 2,944-byte source stays identical after changes
to dist/, build/, .lake/ and workspace metadata. Full checks await component cleanup.

Current interface agreement: profiles are SQLite versions only (`sqlite351`,
`sqlite346`). The example uses explicit BEGIN, ALTER, literal INSERT, COMMIT and
literal UPDATE. A documented timestamp/duration instantiate runtime values;
no framework-wide equivalence is claimed. The reasonable baseline precedes
optimizer-created statistics tables. Source review confirms missing or NULL
shell decodes to no recorded shell; preserving old stored fields preserves
decoder inputs, without claiming a formalization of every application query.

Core review checkpoint: reusable literal DML explicitly checks lossless affinity,
integer/NULL key comparisons, constraint validity and deterministic rowid allocation.
Open-transaction outcomes distinguish persisted and visible storage. Old additive
proof conveniences require a syntax guard before entering the generic semantics.
The semantic-subset document records those restrictions. Markdown checks pass;
Lean and example proof validation remain in progress in the formal workspace.
