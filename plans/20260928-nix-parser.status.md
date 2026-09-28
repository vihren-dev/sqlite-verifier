# Nix-only parser build status

Created: 2026-09-28. Status: DONE.

Contract: [task](20260928-nix-parser.task.md).

Implemented in `build-support/default.nix`: Nix verifies pinned upstream hashes,
builds Lemon, invokes the grammar adapter, and compiles both native parsers.
`parser/generate.py` retains token-inventory validation. Removed `parser/build.py`
and `parser/build_cache.py`. `just parser` links the Nix artifacts at the existing
checkout paths, retaining a GC root at `build/parsers`.

Retired nine custom build/cache scenarios with their historical evidence retained
in `tests/case-inventory.json`; added one focused generator regression. All 414
active inventory identities match fresh pytest collection. Updated the reviewed
unit selection, source runner and current build documentation.

Validation on aarch64-darwin:
- Real Nix parser build passes both releases and every upstream checksum.
- Repeated `just parser`/`just build` reuse the same output without compilation;
  the complete local library/checker build and loader-root generation pass.
- A temporary altered upstream grammar fails the real Nix build at checksum verification.
- 97 parser, translation, schema-generation and loader cases pass.
- 16 native/model conformance and proof/grammar evidence cases pass.
- 29 source-runner and unit-cache contract cases pass.
- Nix `unitChecks`: 58 cases and 43 subtests pass.
- Documentation links outside three pre-existing draft documents pass.

Linux native builds and the full installed-package suite were not rerun locally.
The unrelated pre-existing draft documents remain unmodified and uncommitted.
