# Lean source staging

`migration_check.compile.compile_project` accepts the pinned Lean sysroot and
library directory, four selected Lean source paths (`requirements`,
`interpretation`, `next_interpretation`, `proofs`), parent-generated `sql_inputs`
source, and an empty private `workspace`. Its result contains `trusted` and
`candidate` artifact directories, source `hashes`, and compiler `diagnostics`.
`CompileError` identifies the failed phase and source; malformed dependency
closures raise `ValueError`. `EXPECTED_SOURCE` provides the fixed convenience
`Generated.expected` declaration for inspectable exports.

The pinned compiler's `--deps-json` header parser discovers imports without
elaborating user code. Only reachable local `.lean` sources are snapshotted.
User binaries and Lake settings are ignored. Missing or ambiguous sources,
cycles, filesystem name collisions, and candidate-only dependencies in approved
sources are rejected. Physical file identities prevent case aliases and hardlinks
from bypassing selected-file exclusions. Explicitly supplying the same source for
multiple roles authorizes that source for those roles.

Approved Requirements and Interpretation closures compile without access to
candidate sources or outputs. SqlInputs compiles separately with only the pinned
library available. Candidate NextInterpretation, Generated and Proofs then compile
with approved artifacts read-only. Each compiler gets a fresh writable scratch
directory and a bounded sandboxed process. After it exits, the parent copies only
expected regular artifact companions, rejecting symlinks (including ancestors),
hardlinks, and paths outside scratch. No generated executable is run.

Hash keys identify exact source snapshots as `approved/<module>.lean`,
`candidate/<module>.lean`, and `generated/SqlInputs.lean`. These include transitive
source dependencies and the fixed target alias. The caller controls sysroot,
library, generated SQL data, and workspace ownership; it must subsequently invoke
the independent kernel gate. Successful compilation alone is not verification.

`timeout 180 python3 -m tests.compilation_test` exercises real sandboxed Lean
compilation and the kernel gate, source closure discovery and hashes, binary
exclusion, approved/candidate isolation, and rejected artifact aliases. It passed
locally on aarch64-darwin. Linux runtime and sandbox behavior require hosted CI
confirmation; no blanket `/nix/store` read permission is granted by this compiler.
