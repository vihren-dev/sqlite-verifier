# Native runtime packaging

Created: 2026-09-24. Status: IN PROGRESS.

The declared macOS ARM64 and Linux x86-64 platforms have installable verifier
archives containing the checked CLI, pinned parser/checker/library, and Lean
4.33.0 runtime. Installation requires Nix but no network downloads or ambient
Python, Lean, or bubblewrap selection. Existing Nix signature checking remains
active. The installation keeps required store closures alive and can be removed
without changing source projects or other installations.

A package smoke test extracts an archive into a fresh directory, installs it,
and verifies the real positive example with controlled environment variables and
no elan. It also exercises a negative result and a malformed/unsupported input.
Both platform jobs must run the same shared checks before packaging. Tagged
release publication waits for both platform jobs and publishes their checksums
and archives; no tag or public release is created by this task alone.

Important boundaries are the compiled checker/library path layout, all Lean
object/IR files needed by arbitrary standard tactics, dynamic native dependencies,
Python isolated mode, Nix closure signatures and garbage-collection roots, and
GitHub's per-asset size limit. Packaging is engineering evidence; real-pilot
acceptance and review of product requirements remain separate.
