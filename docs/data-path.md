# Data path: `prepare` and `verify-bundle`

[ADR 0003](adr-0003-agent-proof-preparation.md) separates proof preparation, which
the agent controls, from acceptance, which the verifier controls. Both commands run
under the same [trusted-execution assumption](trust-boundary.md) as `verify`.

## Commands

```sh
migration-check init --project candidate \
  --requirements approved/Requirements.lean --interpretation approved/Interpretation.lean

migration-check prepare --profile 3.51.0 \
  --schema schema.sql --requirements approved/Requirements.lean \
  --interpretation approved/Interpretation.lean --migration candidate/migration.sql \
  --project candidate --output proof.bundle [--cache DIR | --no-cache] [--format json]

migration-check verify-bundle --profile 3.51.0 \
  --schema schema.sql --requirements approved/Requirements.lean \
  --interpretation approved/Interpretation.lean --migration candidate/migration.sql \
  --bundle proof.bundle [--approved-baseline approved/baseline.json] \
  [--cache DIR | --no-cache] [--format json]

migration-check clean-cache

# The phases that prepare runs, one at a time (ADR 0010 section 10):
migration-check generate CONTRACT-AND-SQL-OPTIONS --project candidate   # after a SQL change
migration-check check --project candidate                              # after each proof edit
migration-check audit --project candidate                              # before export
migration-check export CONTRACT-AND-SQL-OPTIONS --project candidate --output proof.bundle
```

`check` is the same as `lake build` in the project, and the editor's Lean server
gives the same result for one file. `audit` builds the generated module `Check`, whose
command fails on an axiom outside the gate's allowlist (including `sorryAx`) or an
import that the verifier does not have; it is not part of the per-edit loop because
it loads `Lean`, about 0.5 s. `generate` refuses a lakefile that turns off kernel
checking (`debug.skipKernelTC`). `prepare` audits before it exports; `export` alone
builds and exports without the audit, so bundles from any tool reach `verify-bundle`.
The audit decides nothing; `verify-bundle` does.

**`init`** turns a folder with `NextInterpretation.lean` and `Proofs.lean` into a
*proofs project* ([ADR 0010](adr-0010-lake-builds-and-artifact-cache.md)): it writes
a `lakefile.toml` that reads the approved contract in place and lists the
contract, generated and candidate modules, a `lean-toolchain`, and the link
`.belay/runtime` to the installation, which the lakefile requires. From then on
the lakefile belongs to the user. After `prepare` has written the generated
modules once, `lake build` and the editor's Lean server work on the project
without the verifier.

**`prepare`** writes the generated modules into the project's `Generated/`
folder (only files whose content changed), checks that the lakefile reads the
given approved folder and lists every module, builds the project with Lake and
writes the bundle to `--output`. Lake compiles only changed modules and reuses
outputs from the artifact cache. `prepare` runs in the agent's trust domain and is
a convenience: an agent may produce the bundle with its own tools instead.

**`verify-bundle`** parses the actual schema and migration SQL itself, builds the
starting schema and the approved contract with Lake in its own workspace (it never
reads the user's lakefile), and runs `migration-bundle-checker` with the frontend's
[structural record](#generated-inputs-record). The checker never compiles candidate source.
It imports the pinned library and trusted modules only from the verifier
installation, rejects any exported declaration that differs from a trusted one,
replays the rest in the Lean kernel, reconstructs the verification target itself
and applies the same axiom policy as the [kernel gate](kernel-gate.md).

## Reports and exit codes

With `--format json` each command prints one JSON object.

| Command | Result | Report | Exit code |
| --- | --- | --- | --- |
| `init` | Project written | `{"status": "INITIALIZED", "project": PATH, "lakefile": PATH}` | 0 |
| `prepare` | Bundle written | `{"status": "PREPARED", "bundle": PATH, "compiled_modules": [...], "warnings": [...]}`; a warning names approved code that runs during elaboration (`#eval`, `run_cmd`, `initialize`, syntax extensions), whose cached outputs can differ from fresh ones | 0 |
| `verify-bundle` | Proof checked | `{"status": "VERIFIED", "profile": ..., "statements": N, "inputs": {...}, "compiled_modules": [...]}`; `inputs` holds the same hashes as `verify` plus `"bundle"`, the SHA-256 of the bundle file | 0 |
| `clean-cache` | Other builds' folders removed | `{"status": "CLEANED", "root": PATH, "removed": [...]}` | 0 |
| `verify-bundle` | Refutation checked | `{"status": "VIOLATED", "message": ..., "compiled_modules": [...]}` | 1 |
| either | Anything else | `{"status": "INPUT_ERROR" \| "UNSUPPORTED" \| "UNVERIFIED", "message": ...}` | 1 |

`compiled_modules` lists the modules that Lake compiled in this run; modules that
came from the cache are not listed.

**The cache.** `--cache DIR`, else the variable `BELAY_CACHE_DIR`, else a per-user
folder (`$XDG_CACHE_HOME/belay/` or `~/.cache/belay/`, `~/Library/Caches/belay/` on
macOS) with one subfolder for each verifier build; `clean-cache` removes the other
builds' subfolders. `--no-cache` uses a private, empty artifact cache; `prepare`
still reuses the outputs in the project's own `.lake` folder.
Any process that can write to the cache can put outputs into it that later builds
use without compiling, so the caller protects it like the installation. When the
same person or job runs `prepare` and `verify-bundle`, they may share one cache; a
separate verifier environment keeps its own.

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

The frontend writes the request as one JSON object, the structural record of
ADR 0008:

```json
{"version": 2, "release": "3.51.0", "sourceId": "...", "schema": [...], "script": [...]}
```

`schema` and `script` are statement syntax, as `belay.sqlite.syntax` maps the
SQL (see the [conformance case format](conformance-format-v1.md)). Every command
runs `migration-resolver` on the record first. It resolves the schema and the
script in Lean and writes `SchemaInputs.lean` (`Generated.profile`,
`Generated.schema`, `Generated.startCatalog`) and `SqlInputs.lean`
(`Generated.script`, `Generated.resolved`, `Generated.nextCatalog`). A model
restriction returns `UNSUPPORTED` at the byte range of the refused node; a schema
statement that SQLite refuses returns `INPUT_ERROR` with SQLite's message.

The gates do not trust the resolver's output. `migration-proof-checker` and
`migration-bundle-checker` both receive the record and resolve it again
(`packages/sqlite-verifier/GateInputs.lean`). The `.olean` gate requires every compiled generated
declaration to be definitionally equal to its own result. `verify-bundle` does not
compile `SqlInputs.lean`; the checker (`BundleChecker.generatedDeclarations`):

1. requires the compiled `SchemaInputs` declarations to equal its resolution;
2. builds `Generated.script`, `Generated.resolved` and `Generated.nextCatalog` as
   closed definitions from its resolution and has the kernel check them;
3. accepts a bundle's own copies of those three declarations only when they are
   definitionally equal to the constructed ones. Replay always uses the
   constructed declarations.

Other versions, malformed records and records that do not resolve are rejected.
`tests/generated_inputs_test.py` checks that the constructed declarations equal
the compiled resolver output, and that a changed record is rejected.

## Pinned exporter library and driver

The runtime ships `migration-proof-exporter`, built from `packages/verifier-gate/ProofExporter.lean`
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
2. Check the internal interfaces used by `packages/verifier-gate/ProofExporter.lean`, and check Lean's
   declaration-origin and module-import APIs. Keep upstream unsafe/partial
   declaration handling unchanged.
3. Rebuild and run `tests/bundle_test.py` (Nix target `tests.bundle`), which covers
   parity with `verify` and the rejection cases. The exporter tests also check
   the retained bundle byte identities and a candidate in a library namespace.
4. Re-check the exporter's normalization (it removes metadata and sets `let`
   nondep flags to false). `packages/verifier-gate/BundleChecker.lean` applies the same normalization when
   comparing protected declarations.

## Tests

Each property is checked at one layer. "Unit" tests need no Lean; "checker" runs
`migration-bundle-checker` directly on compiled inputs; "end to end" runs
the public launcher from the source runtime (Nix target `tests.bundle`);
"installed" runs the offline-installed archive (`just runtime-package`).

| Property | Layer | Test |
| --- | --- | --- |
| The positive, refutation and Atuin examples get their expected status, trusted imports and input bindings; preparation of the small example is deterministic | End to end | `tests/proof_exporter_test.py::test_current_native_export` |
| The allowed-failure example is `VERIFIED` | End to end | `tests/bundle_test.py::test_allowed_failure_through_data_path` |
| The application-key example is `VERIFIED` and its preparation is deterministic | End to end | `tests/bundle_test.py::test_application_key_bundle_repeatability` |
| `sorry`, a forbidden axiom and a proof of another statement are `UNVERIFIED` | End to end | `tests/bundle_test.py::test_invalid_proof_rejected` |
| A bundle built against an altered approved contract is rejected | End to end | `tests/bundle_test.py::test_bundle_from_altered_contract_rejected` |
| A changed default is rejected by both source verification and bundle verification | End to end | `tests/constant_default_example_test.py::test_changed_default_rejects_original_certificate` |
| A bundle is bound to the SQL it was prepared for | End to end | `tests/bundle_test.py::test_bundle_bound_to_prepared_sql` |
| One file may supply both interpretations: the project's `NextInterpretation` imports the approved one | End to end | `tests/bundle_test.py::test_shared_interpretation_file` |
| `prepare` compiles only modules affected by a SQL edit, and the bundle still verifies | End to end | `tests/bundle_cache_test.py::test_sql_edit_reuses_modules_without_sql_inputs` |
| `verify-bundle` compiles nothing on a second run with the same cache | End to end | `tests/bundle_cache_test.py::test_verify_bundle_reuses_its_lake_cache` |
| The installed runtime is a Lake package that Lake replays; the bounded Lake build reuses its cache and names a failed module | End to end | `tests/lake_runtime_package_test.py` |
| Proofs projects: runtime link, generation only of changed files, starting lakefile, contract folder and module-list checks | Unit | `tests/test_proofs_project.py` |
| Workspace lakefile and Lake output reading; cache location and cleanup | Unit | `tests/test_lake_workspace.py`, `tests/test_cache_location.py` |
| `audit` rejects `sorry`, an own axiom and an outside import, naming each; `generate` is stable and refuses `debug.skipKernelTC` | End to end | `tests/project_phases_test.py` |
| `prepare` warns about approved code that runs during elaboration | End to end | `tests/prepare_warning_test.py` |
| The installed commands give `VERIFIED`, `VIOLATED` and a wrong-SQL rejection | Installed | `tests/runtime_package_test.py::test_installed_data_path` |
| Constructed generated declarations match the resolver output; tampered records are rejected | Checker | `tests/generated_inputs_test.py` |
| Narrowed gate imports keep every existing gate rejection | End to end | `tests/kernel_gate_test.py` (Nix target `tests.kernel`) |

## Measurements

See the [P1 results](../experiments/adr-0003-latency/p1-results.md) and the
[latency experiments](../experiments/adr-0003-latency/README.md).
