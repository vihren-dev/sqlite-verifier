# Data path: `prepare` and `verify-bundle`

[ADR 0003](adr-0003-agent-proof-preparation.md) separates proof preparation, which
the agent controls, from acceptance, which the verifier controls. Both commands run
under the same [trusted-execution assumption](trust-boundary.md) as `verify`.

## Commands

```sh
migration-check prepare --profile 3.51.0 \
  --schema schema.sql --requirements approved/Requirements.lean \
  --interpretation approved/Interpretation.lean --migration migration.sql \
  --next-interpretation NextInterpretation.lean --proofs Proofs.lean \
  --workspace agent-build --output proof.bundle [--format json]

migration-check verify-bundle --profile 3.51.0 \
  --schema schema.sql --requirements approved/Requirements.lean \
  --interpretation approved/Interpretation.lean --migration migration.sql \
  --bundle proof.bundle [--approved-baseline approved/baseline.json] [--format json]
```

**`prepare`** compiles the approved contract and the candidate modules in the
persistent `--workspace`, then writes the bundle to `--output`. It rebuilds a
candidate module only when its source or something it imports changed: a proof
edit recompiles the proof, while a migration edit recompiles only the modules that
import the generated SQL inputs. The workspace is an agent-side cache. Deleting it
is always safe, and `verify-bundle` never reads it. `prepare` is a convenience: an
agent may produce the bundle with its own tools instead.

**`verify-bundle`** parses the actual schema and migration SQL itself, compiles (or
reuses from the opt-in stage store) the approved contract and generated inputs,
and runs `migration-bundle-checker`. The checker never compiles candidate source.
It imports the pinned library and trusted modules only from the verifier
installation, rejects any exported declaration that differs from a trusted one,
replays the rest in the Lean kernel, reconstructs the verification target itself
and applies the same axiom policy as the [kernel gate](kernel-gate.md).

## Reports and exit codes

With `--format json` each command prints one JSON object.

| Command | Result | Report | Exit code |
| --- | --- | --- | --- |
| `prepare` | Bundle written | `{"status": "PREPARED", "bundle": PATH, "compiled_modules": N, "reused_modules": M}` | 0 |
| `verify-bundle` | Proof checked | `{"status": "VERIFIED", "profile": ..., "statements": N, "inputs": {...}}`; `inputs` holds the same hashes as `verify` plus `"bundle"`, the SHA-256 of the bundle file | 0 |
| `verify-bundle` | Refutation checked | `{"status": "VIOLATED", "message": ...}` | 1 |
| either | Anything else | `{"status": "INPUT_ERROR" \| "UNSUPPORTED" \| "UNVERIFIED", "message": ...}` | 1 |

Statuses mean what they mean for `verify`. A malformed, incompatible or incomplete
bundle, a failed export or a failed candidate compile is `UNVERIFIED`. A bundle
prepared against different SQL, schema or approved sources is rejected as a
modified protected declaration, so it cannot verify another request.

## Bundle format, version 1

One UTF-8 file:

1. A JSON header line: `{"bundle": 1, "trusted_imports": ["Module", ...]}`. It names
   the trusted-library modules whose declarations the export references but omits.
   The checker imports them only from the sysroot and verifier library.
2. A [lean4export](https://github.com/leanprover/lean4export) NDJSON 3.1.0 export
   of the proof, next/failure interpretations and their dependencies. Declarations
   from `Init`, `Std`, `Lean` and `SqliteVerifier` are omitted, using the pinned
   exporter's `--skip-trusted` option (see below).

Other versions are rejected. The format is for trusted execution; hardened
decoding of hostile bundles is part of the
[deferred trust design](adr-0003-trust-extension.md).

## Pinned exporter and its patch

The runtime ships lean4export at tag `v4.33.0`
(`15f6055e299ad5b89345e533cc2192f4cc00f659`) with
`build-support/lean4export-skip-trusted.patch`, built by
`build-support/lean4export.nix`. The patch adds `--skip-trusted`. Decision
(2026-09-29): keep the pinned patch for now. Proposing a general "omit declarations
from these modules" option upstream is a separate, owner-approved step. When Lean
is upgraded:

1. Move the pin to the lean4export tag matching the new Lean version and update the
   hash in `lean4export.nix`.
2. Reapply the patch; it touches only `Export.lean`'s state and `dumpConstant`.
3. Rebuild and run `tests/bundle_test.py` (Nix target `tests.bundle`), which covers
   parity with `verify` and the rejection cases.
4. Re-check the exporter's normalization (it removes metadata and sets `let`
   nondep flags to false). `BundleChecker.lean` applies the same normalization when
   comparing protected declarations.

## Tests

Each property is checked at one layer. "Unit" tests need no Lean; "end to end" runs
the public launcher from the source runtime (Nix target `tests.bundle`);
"installed" runs the offline-installed archive (`just runtime-package`).

| Property | Layer | Test |
| --- | --- | --- |
| Same status as `verify` for the positive, refutation, allowed-failure and Atuin examples | End to end | `tests/bundle_test.py::test_status_parity` |
| `sorry`, a forbidden axiom and a proof of another statement are `UNVERIFIED` | End to end | `tests/bundle_test.py::test_invalid_proof_rejected` |
| A bundle built against an altered approved contract is rejected | End to end | `tests/bundle_test.py::test_bundle_from_altered_contract_rejected` |
| A bundle is bound to the SQL it was prepared for | End to end | `tests/bundle_test.py::test_bundle_bound_to_prepared_sql` |
| One file may supply two roles, as for `verify` | End to end | `tests/bundle_test.py::test_shared_interpretation_file` |
| `prepare` keys: an edit invalidates only the edited module and its importers | Unit | `tests/test_module_keys.py` |
| `prepare` reuses modules after a SQL edit and the bundle still verifies | End to end | `tests/bundle_test.py::test_sql_edit_reuses_modules_without_sql_inputs` |
| Stage store: verified restore, damaged or malformed entries miss, unwritable store tolerated, identity follows the runtime | Unit | `tests/test_stage_store.py` |
| `verify` with a stage store: same results, fresh fallback, approved closures excluded unless eligible | End to end | `tests/stage_reuse_test.py` |
| The installed commands give `VERIFIED`, `VIOLATED` and a wrong-SQL rejection | Installed | `tests/runtime_package_test.py::test_installed_data_path` |
| Narrowed gate imports keep every existing gate rejection | End to end | `tests/kernel_gate_test.py` (Nix target `tests.kernel`) |

## Measurements

See the [P1 results](../experiments/adr-0003-latency/p1-results.md) and the
[latency experiments](../experiments/adr-0003-latency/README.md).
