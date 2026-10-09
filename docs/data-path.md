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
reuses from the opt-in stage store) the starting schema and approved contract,
and runs `migration-bundle-checker` with the frontend's
[generated-inputs record](#generated-inputs-record). The checker never compiles candidate source.
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
   The checker imports them only from the sysroot, application library and model library.
2. A [lean4export](https://github.com/leanprover/lean4export) NDJSON 3.1.0 export
   of the proof, next/failure interpretations and their dependencies. Declarations
   supplied by the checker's trusted import closure are omitted. The exporter
   uses each declaration's origin module, so a candidate module under a library
   namespace is still exported.

Other versions are rejected. The format is for trusted execution; hardened
decoding of hostile bundles is part of the
[deferred trust design](adr-0003-trust-extension.md).

## Generated-inputs record

`verify-bundle` does not compile `SqlInputs.lean`. It writes the frontend's result
as one JSON object and passes it to the checker:

```json
{"version": 1, "profile": "sqlite351", "schema": [...], "nextSchema": [...], "script": [...]}
```

`schema`, `nextSchema` and `script` use the structural encoding of
[conformance format v1](conformance-format-v1.md), with indexes in declaration
order. The checker (`BundleChecker.generatedDeclarations`):

1. requires `schema` to equal the compiled `Generated.startSchema`;
2. builds `Generated.nextSchema`, `Generated.script` and `Generated.profile` as
   closed definitions and has the kernel check them;
3. accepts a bundle's own copies of those three declarations only when they are
   definitionally equal to the constructed ones. Replay always uses the
   constructed declarations.

Other versions and malformed records are rejected. SQL admission and validation
still run in the Python frontend before the record is written, and the reported
`generated/SqlInputs.lean` hash is unchanged. `verify` and `prepare` still compile
`SqlInputs.lean`; `tests/generated_inputs_test.py` checks that both forms agree.

## Pinned exporter library and driver

The runtime ships `migration-proof-exporter`, built from `ProofExporter.lean`
under Lean 4.34.1. It uses unpatched lean4export at tag `v4.34.0`
(`076e8e57707e813375e8f9da8bf989799ace9680`), pinned by
`build-support/lean4export.nix`. `prepare` passes `--omit=SqliteVerifier` plus
one `--omit=MODULE` for every trusted import in the same bundle header.
The driver marks exactly the declarations from those modules' import closure as
visited before invoking upstream emission. Approved and generated declarations
remain in the export for the checker to compare. Module origins work across
Lake packages and do not depend on a model package's name or namespace.
Lean resolves a package directory before its individual modules. Preparation
uses a temporary merged view when a caller-owned module shares a package with
the installed library. Each artifact keeps the existing search-root precedence;
an installed trusted artifact wins over a candidate with the same path. The
checker continues to load its trusted base from the original installed roots.

The driver uses lean4export's internal `State.visitedConstants`, `M.run`,
`initState`, `dumpMetadata` and `dumpConstant` interfaces. Upstream can change
these interfaces without notice. When Lean is upgraded:

1. Select the matching lean4export release and check that it builds under the new
   Lean version. Update its commit and hash in `lean4export.nix`; a patch-level
   Lean release can use the matching minor-release exporter tag.
2. Check the internal interfaces used by `ProofExporter.lean`, and check Lean's
   declaration-origin and module-import APIs. Keep upstream unsafe/partial
   declaration handling unchanged.
3. Rebuild and run `tests/bundle_test.py` (Nix target `tests.bundle`), which covers
   parity with `verify` and the rejection cases. The exporter tests also check
   the retained bundle byte identities and a candidate in a library namespace.
4. Re-check the exporter's normalization (it removes metadata and sets `let`
   nondep flags to false). `BundleChecker.lean` applies the same normalization when
   comparing protected declarations.

## Tests

Each property is checked at one layer. "Unit" tests need no Lean; "checker" runs
`migration-bundle-checker` directly on compiled inputs; "end to end" runs
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
| Constructed generated declarations match the Lean emitter; tampered records are rejected | Checker | `tests/generated_inputs_test.py` |
| Narrowed gate imports keep every existing gate rejection | End to end | `tests/kernel_gate_test.py` (Nix target `tests.kernel`) |

## Measurements

See the [P1 results](../experiments/adr-0003-latency/p1-results.md) and the
[latency experiments](../experiments/adr-0003-latency/README.md).
