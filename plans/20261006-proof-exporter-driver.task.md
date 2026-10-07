# Proof exporter driver

Status: DONE. Created 2026-10-06. Completed 2026-10-07.

## Outcome

The installed runtime ships a repository-owned exporter executable built
against unpatched lean4export v4.34.0 under Lean 4.34.1. The exporter omits
exactly the declarations whose origin modules belong to the import closure
of the checker's trusted base. `prepare` derives that omission list from
the same trusted imports that it writes into the version-1 bundle header,
plus the protected library base always imported by the checker.

No lean4export patch or separately built patched executable remains.
Candidate declarations with library-like module names are exported and
kernel-checked. Omission depends on module origin and actual imports,
rather than namespace prefixes. This works for model modules supplied by
the separate Lake package planned in T10.
Compiler and exporter lookup support split package directories without
changing file precedence: installed trusted artifacts remain ahead of
caller artifacts with the same relative module path.

Source: [issue #29](https://github.com/vihren-dev/sqlite-verifier/issues/29).

## Acceptance

Actual small-success, checked-refutation and Atuin bundles are byte-identical
to the T03 patched-exporter baselines under Lean 4.34.1. The retained hashes,
input bindings and `VERIFIED` / `VIOLATED` statuses match on both supported
platforms. Small and refutation baselines contain 11,358 and 14,584 bytes;
Atuin contains 1,541,403 bytes. Byte comparison uses retained baseline bytes
or their cryptographic digests, not a newly chosen expected output.

A bounded end-to-end test compiles a candidate module under `SqliteVerifier`,
exports its used declaration, and verifies the resulting bundle. Focused
tests cover explicit trusted-import closure, transitive imports, missing
omission modules and malformed arguments. A module merely sharing a trusted
namespace is not omitted. Existing bundle attack and generated-input parity
tests retain their rejection behavior.

Installed-runtime tests exercise `prepare` and `verify-bundle` through the
new executable on both supported platforms. `just test` and relevant Nix
source-input and packaging checks pass. Tests and subprocesses retain bounded
timeouts. Internal lean4export API dependencies are documented as toolchain
upgrade constraints. Independent review and required final owner review
precede release or merge of trusted-boundary changes.

## Constraints

`BundleChecker.lean` and `GateCore.lean` define the trusted base and kernel
replay checks. `migration_check/prepare.py:export_bundle` owns the header and
exporter invocation; source and contract discovery identify trusted imports.
`build-support/lean4export.nix` pins the dependency source.
`build-support/default.nix`, `runtime.nix`, `sources.nix` and `lakefile.toml`
build and ship executables. `packaging/build_runtime.py` exports the complete
installed Nix closure; its offline archive includes the new driver.

The driver depends on lean4export's `visitedConstants`, `M.run`, `initState`
and `dumpConstant` interfaces. Inspect their actual pinned definitions before
using the issue prototype. Origin indices refer to the environment that
contains candidate and trusted modules; namespace names alone do not prove
trusted origin. Approved and generated declarations must remain exported
where the existing bundle comparison requires them.

T03 receipts are immutable baselines in
`reports/20261006-lean-4341-upgrade-{darwin,linux}.json`. The reviewed upgrade
revision is `6917e3c8`; its approved integration was merged through PR #43 as
`bc9e2dce` on 2026-10-07. The owner approved PR #47 at exact reviewed head
`07dc71b3` on the same date. The publication integration preserves that exporter,
import-view, source-pin and baseline code. Main's accepted engine-settings
caller changes have a separate current-input receipt; the historical native
receipts keep their original source/runtime identities. Both final native jobs pass in CI `37598926394` at `eec6d08e`. PR #47
merged normally as `2e01c49a`, with no tree difference from that tested
head. Delivery is complete. This task grants no release approval.
