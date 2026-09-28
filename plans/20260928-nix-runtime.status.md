# Nix-owned runtime status

Created: 2026-09-28. Status: DONE.

Contract: [task](20260928-nix-runtime.task.md).

`just build` now builds the complete immutable Nix runtime, including Lean,
the parser and checker. `closureInfo` supplies the exact proof sandbox roots.
Python native dependency discovery, copied-ELF relocation and their obsolete
implementation tests have been removed.

Packaging exports a Nix content-addressed closure, verifies it and retains normal
import integrity checks without new trusted keys. Installation links the imported
runtime and retains its closure with a GC root. Documentation and active/unit
case inventories reflect the new build and installation paths.

Validation on aarch64-darwin:

- Native Nix runtime build passed.
- 18 packaging, manifest, resource and CI regression tests passed.
- 67 kernel-gate, sandbox and source-identity tests passed.
- Nix unitChecks passed: 56 tests and 43 subtests.
- Actual content-addressed archive export and verification passed (~1.1 GB).
- All 19 installed runtime and Atuin tests passed, including offline installation
  and poisoned-environment checks (127.40 seconds).
- Full collection reports 402 active cases, matching the inventory.
- Documentation links passed excluding the three pre-existing unrelated draft
  documents, whose broken links remain outside this change.

Linux native build/install execution remains for CI; this host is macOS.
The unrelated drafts in docs/0003-component-research.md,
docs/adr-0002-compile-project-cache.md and docs/adr-0003-agent-proof-preparation.md
are preserved and excluded from this commit.
