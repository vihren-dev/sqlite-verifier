# Selection isolation evidence — 2026-09-28

Task: [pytest/Nix builds](20260928-pytest-nix-builds.task.md), ADR0001 T4.
Author: inventory/conformance member. Base: reviewed integration `092412ca`.
Scope: actual individual selections; the lead owns the final full-source reversed
run and installed-runtime ordering. Overall acceptance remains pending.

The integrated inventory contains 401 unique IDs: 395 source, 19 installed,
with 13 shared Atuin IDs. Every one of the 244 frozen legacy mappings remains.
The inventory refresh and the four independently reviewed descendant-cleanup
additions are already part of the base commit.

A source-only receipt audit requires exactly one selected ID, exit zero and passed
setup/call/teardown phases. It scans retained build reports in the four team
workspaces and never treats an installed receipt as source evidence. The audit
finds the prior CLI19, Atuin13, kernel19, compilation17, early-baseline7 and timeout4
individual checks plus other previous selected checks.

A new sequential batch ran 139 previously unverified resource-free cases, each
in a separate pytest process, in the existing pinned Nix development environment.
Every selection passed. Each command has a 90-second outer deadline, shares run ID
`isolation-6e018bf3-3588-47d2-b67b-4c7ebe4b6aad`, and explicitly selects immutable
runtime `/nix/store/00b6q3j0lwsh55597prmyv63awq5bsff-sqlite-verifier-runtime-1`.
No parser, Lean or Nix derivation build was performed.

Artifacts in this workspace:

- `build/isolation-resourcefree-results.json`: exact 139 IDs and exit codes.
- `build/test-results/source/isolation-resourcefree-*.json`: independent phase reports.
- `build/isolation-resourcefree-*.log`: complete individual pytest output.
- `build/selection-isolation-audit.json`: all 395 source IDs with matching receipts.

After this batch, 225 of 395 source cases have observed passing standalone
reports. The remaining 170 require declared resources. The lead will run the
two native-reuse cases against its already-built source checkout; this member
will run the other 168 after the lead releases the shared heavy test window.
The pending set includes 76 parser cases and 41 source-identity relations.
These counts describe actual evidence, not an inference from fixture structure.
