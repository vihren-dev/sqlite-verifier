# Incremental parser compilation

Created: 2026-09-25. Status: IN PROGRESS.
Task: [development resources](20260925-development-resources.task.md).

The root task authorizes incremental parser builds while preserving upstream
validation and both independent release profiles. This component owns only the
parser builder/cache helper and focused tests. Atuin runner work is preserved
separately in Jujutsu change sqozxswn, snapshot64062d08; it is not part of this unit.

The cache is per release, content-based, and records complete output
hashes. Every call validates pinned upstream sources before checking the cache.
The compiler, generator/interpreter, source and compile-environment identities
participate. Unpinned external compilers conservatively rebuild because a wrapper
or selected SDK can change without its launcher changing. The technical lead
reviewed this boundary; final implementation review is pending.

Initial resource restriction prohibited full-workspace Nix entry, cleanup and
expensive builds. The five focused regressions use tiny temporary fixtures;
after the external disk recovery, the real checks used the small environment.

## Checked implementation

The builder now keeps one content stamp per release, checks every upstream pin on
every invocation, and validates complete generated/output hashes and modes before
reuse. Source/generator, compiler bytes/path, Python bytes/version and relevant
compiler environment are bound. Transient Nix shell variables are excluded;
unknown mutable toolchain overrides conservatively rebuild. Direct cc invocation
continues to ignore make-only CFLAGS/CPPFLAGS/LDFLAGS; those strings still
participate in invalidation. No custom dependency graph or toolchain discovery.

The external disk state recovered to 50 GiB free; the team deleted nothing.
Validation used only the integration engineer's explicit small environment:
`nix develop path:/Users/tzankomatev/work/sqlite-verifier-integration/nix`.
The real first build passed under timeout120. Two subsequent fresh shell entries
replaced `build.run` with a raising mock and built both releases successfully,
proving zero compiler/Lemon calls across shell entries (first hit: 0.033 seconds).
The final bounded batch passed five focused cache tests in 0.128 seconds and both
parser suites (20 grammar scripts each, malformed/limits/byte-span checks).

Focused tests also cover source and generator changes, compiler content and path,
flags, all missing intermediate/output files, corrupted output/stamp, independent
release invalidation, pinned tampering before any tool, failed builds, transient
shell variables and conservative mutable-override handling. Final independent
technical-lead review is pending; this does not complete the wider resource task.

## Independent review and completion

Component status: DONE (2026-09-25). The wider development-resources task remains
in progress with its owner. Ultra technical lead independently reviewed the
source and reproduced all five focused tests (0.145 seconds). Review identified
platform-suffixed Darwin SDK/deployment variables used by the pinned wrapper;
these now participate in identity and mutable-SDK rejection. The deployment
regression isolates that variable after restoring the default compiler.

Final reviewed-source validation: actual both-release build passed; a fresh tiny
shell with every build-tool call forbidden reused both outputs. Five focused tests
passed in 0.138 seconds, followed by both complete existing parser regression
suites. Unknown overrides and purity-enforced environments retain conservative
rebuild behavior; no claim of incremental reuse for arbitrary external tools.
