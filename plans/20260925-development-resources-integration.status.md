# Development resource boundary — integration status

Created: 2026-09-25. Status: DONE (bounded environment unit; parent task integration continues).
Task: [development resources](20260925-development-resources.task.md).

Preserved unfinished Atuin CLI harness in jj change woltywkz, snapshot 1f2379b2;
this repair starts independently from d957dede. No cache, database or volume was
deleted. Disk capacity recovered externally before environment validation.

Moved the pinned flake into the exact two-file nix/ boundary. flake.lock bytes
match d957dede exactly; shell markers identify capture tools and target platform.
Active local/docs/direnv commands use explicit path:./nix. Shared checks require
one capture shell; atuin-native no longer enters Nix recursively. CI routing and
aggregate evidence changes remain parent-owned; incremental parser is separately
owned by conformance review.

Resource preflight rejects environment symlinks/extra files/>1 MiB and less than
10 GiB on distinct workspace, temporary, elan/Cargo and Nix write filesystems. Direct
runtime packaging checks before runtime inspection or copies. Team guidance names
resource ownership, bounded retention and explicit cleanup approval boundaries.

Validation:
- Real bounded Nix metadata test passed for non-Git and Git-parent fixtures.
  Modifying source plus dist/build/.lake/.jj leaves the identical store source,
  NAR hash and 3,264-byte NAR size; snapshot contains exactly the two pin files.
- Three focused resource tests pass (0.023s), including separate temporary-volume
  exhaustion and direct package preflight before external work.
- Actual resource preflight passes after external capacity recovery.
- Explicit tiny capture-shell resource/marker checks and complete just dry-run pass.
  The shell restored externally reclaimed pinned tools; no root-flake entry occurred.
- Pinned Python rerun: all three resource tests pass (0.013s), and both real
  snapshot fixtures again retain exactly the same 3,264-byte source identity.
- Independent Ultra review accepted the boundary and found one missing destination:
  caller-selected CARGO_HOME now receives the same distinct-filesystem preflight,
  with a focused separate-volume failure regression.
- Final Ultra acceptance: independently reproduced all three resource tests in
  0.012s and the actual two-fixture Nix identity test in 0.44s; identical source
  /nix/store/2mav3lrnq9b1cchknycd1j0vixir28j6-source, NAR 3,264 bytes.
  No full build/package is claimed by this unit.
