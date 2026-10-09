# Checked Lean API reference

The public library starts at `SqliteVerifier.lean`. Lean checks Verso names,
terms and computed assertions when it compiles declarations with
`set_option doc.verso true`. The generated HTML includes declaration
documentation, module documentation, types and links to their source lines.

## CLI inputs and proof roles

Use `--schema` for the pre-migration SQL schema and `--profile` for the SQLite
semantic version. Approved `--requirements` defines the logical contract for
states, changes, schema, failures and required outcomes. Approved
`--interpretation` defines the meaning of starting data and its admission condition.

Candidate `--migration` supplies the SQL to verify. Candidate
`--next-interpretation` defines the meanings of resulting data and modeled failure
states. Candidate `--proofs` supplies a proof or refutation of the exact
verification contract. That contract quantifies over every model-conforming
starting database satisfying the approved admission condition under the supplied
schema and profile. Proofs also establish the soundness of the current,
resulting and failure interpretations.

Read each command's input help:

```sh
bin/migration-check verify --help
bin/migration-check prepare --help
bin/migration-check verify-bundle --help
```

`prepare` writes a candidate bundle and reports `PREPARED`. `verify-bundle`
takes that bundle through `--bundle` to check its candidate interpretations and
proofs against the supplied SQL and approved inputs. The
[data path guide](data-path.md) explains these commands and their reports.

## Build and read the reference

From the pinned development shell, build the reference for a committed source
revision:

```sh
jj log -r @- --no-graph -T 'commit_id ++ "\n"'
just reference FULL_COMMIT_HASH
```

Use the full commit hash printed by Jujutsu. The source files in the workspace
must match that commit. After the build, serve the reference locally so its
navigation and search can load the declaration index:

```sh
python3 -m http.server 8000 --bind 127.0.0.1 --directory build/api-reference
```

Open <http://127.0.0.1:8000/> and follow the `SqliteVerifier` module link. The
entry point documentation is in `SqliteVerifier.html`.

CI builds this reference on Linux and macOS under Lean 4.34.1 and retains each
`api-reference-SYSTEM` artifact for 14 days. Download and extract that artifact
and serve that directory with the same command to read it locally. Public
hosting is a separate task.

The reference is built in three steps:

1. `apiReferenceCore` builds the doc-gen4 database for Lean's `Init` and `Std`
   libraries. Its only inputs are the Lean toolchain and doc-gen4, so Nix and
   the CI cache reuse it until one of them changes.
2. `apiReferenceBase` copies the core build, adds our public modules, writes
   all pages with the placeholder `SOURCE-REVISION` in each source link, and
   corrects recursor links on our pages. It does not depend on the commit, so
   Nix and the CI cache reuse it while the Lean sources stay the same.
3. `apiReference` requires `referenceRevision`, the exact source commit. It
   copies the base and puts that commit into each source link, in a few
   seconds. It fails when a placeholder remains or a source link names another
   commit.

The build pins doc-gen4 v4.34.1 and all five dependencies to the revisions in
doc-gen4's own manifest. These include the bundled native code for SQLite,
Markdown and Unicode. Lake uses local paths; the sandbox needs no Git checkout
or network access. The build does not check the pages that doc-gen4 writes:
that would test doc-gen4, not this repository (ADR 0009).

`just documentation-inventory` checks every authored public declaration,
constructor and structure field in the compiled import closure. `just test`
and `just test-full` include this gate. Missing documentation, ordinary
Markdown and unclassified source declarations fail the gate. The inventory
joins the compiler's original binder references with exact parser selections;
generated recursors, deriving helpers and implicit constructors have explicit
exclusion evidence. Direct Verso metadata establishes checked documentation;
inherited documentation does not replace a declaration's own docstring.
Temporary declarations in checked documentation code blocks are excluded only
when their compiler binder positions lie in a compiled Verso comment range.

doc-gen4 4.34.1 links to generated recursors but writes no anchor for them.
On our pages, such links point to the existing parent type. The build fails
when no link needs this correction: then doc-gen4 may have fixed the bug, and
the correction can be removed.

`reference-check.json` records the number of public modules, the corrected
links, the source revision and the source links.
`doc-gen4-sources.json` records the generator dependency pins.
`just documentation-inventory` writes `public-doc-inventory.json`, with
authored coverage, exact module and declaration names, zero-based line and
UTF-16 column selections, source hashes, compiler reference hashes and every
generated-declaration exclusion. The reference does not contain it.
Documentation tools are separate Nix targets and are absent from the installed proof runtime.
Use `bin/migration-check --help` for CLI commands and options.
