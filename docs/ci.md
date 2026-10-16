# Continuous integration

CI uses Nix to cache builds and expensive hermetic pytest suites. The earlier
[ADR 0001](adr-0001-pytest-and-nix-ci.md) unit-result receipts and coverage
aggregation have been superseded by [Nix test targets](../build-support/README.md).

`.github/workflows/ci.yml` runs the verifier checks on Linux for pull requests.
Pushes to `main`, release tags, manual requests and the nightly schedule run
those checks on both native platforms. On pull requests, macOS skips both the
verifier checks and the API reference build.
Local macOS `just test` results remain required for verifier acceptance.

`tests/ci_scope.py` selects the checks from the files that differ from the pull
request base:

| Scope | Selected when | Recipes |
| --- | --- | --- |
| `docs` | only Markdown documentation and review records changed, including on a `main` push | link checks, no build |
| `test` | any other change | `just test-full` |
| `infrastructure` | build definitions or shared test infrastructure changed | `just test-full test-nix` |
| `packaging` | archive contents, installation or runtime discovery changed | `just test-full runtime-package` |
| `package` | both of the above, other `main` pushes, tags, manual and nightly runs | `just package` |

Every scope checks the review log with `tools/review_log_check.py`. Each review
and each resolution is one file, `reviews/ID/review.json` or
`reviews/ID/resolution-N-SECOND.json`, so parallel branches never change the
same file. Each file must hold a valid record at the path that its record
determines, and each record file of the base commit must be present with the
same bytes. Other files under `reviews/` fail the check. The review statistics
use the date of a resolution to find its latest outcome.

Linux builds the [checked API reference](api-reference.md) for pull requests.
Main, tags, manual and nightly runs build it on both native platforms for
non-documentation scopes. They use the
pinned Nix environment with the checkout's full commit hash for source links.
Only the last, cheap step uses that hash. The expensive base build does not, and
`tools/ci_store_gc.py` keeps it in the saved cache, so a run whose Lean sources
match the cache reuses it.
CI retains `api-reference-SYSTEM` for 14 days, including when a later check
fails. `just documentation-inventory` checks authored Verso coverage.
Documentation dependencies stay outside the installed proof runtime.
The complete job has a 75-minute limit. The reference phase keeps its
30-minute limit. Individual compiler, suite and installer deadlines remain
unchanged; a job that reaches its aggregate limit fails.

Each complete check invocation enters the pinned Nix environment once. `tools/ci_checks.py`
checks resources, builds the runtime and
invokes the selected recipe. Darwin first builds the identical `tests.bundle`
target with sandboxing enabled and fallback disabled. Its output is linked at
`build/nix-tests-bundle` for artifact retention. A bundle failure stops the job
before the complete recipe starts model or upstream test builders. Linux keeps
the complete recipe's current schedule.

The prebuild retains the 900-second Nix build deadline; the bundle tests keep
their per-test limits, described below. The
[dated evidence](../reports/20261007-darwin-bundle-scheduling/README.md)
distinguishes the earlier hosted failures from the isolated local pass.

`just test-full` builds independent Nix test targets
with `nix-build -A tests`, among them these; the flake exposes the same derivations as
`checks.<system>`:

- `tests.kernel`: real Lean compilation and proof-checker replay attacks.
- `tests.model`: production SQL translation and concrete Lean model assertions,
  compared with pinned native SQLite on authored and generated cases.
- `tests.frozen`: replay and classification of the frozen corpora (v1 to v20)
  and checks of the retained evidence reports.
- `tests.corpora`: complete validation of each locked frozen corpus.
- `tests.mutants`: mutants of name resolution, each built as a changed copy of the
  Lean packages; every mutant must change the verdict of an authored model case.
- `tests.harness`: fast acquisition, storage, profile and workload checks of the
  conformance harness.
- `tests.sample`: all frozen v4 authored and synthetic cases plus a stable
  upstream sample, with fresh native replay and model classification within
  120 seconds.
- `tests.upstream`: Tcl capture, sampling and import-fidelity checks.
- `tests.atuin`: the Atuin application CLI scenarios.
- `tests.cli`: public-entrypoint acceptance and adversarial input scenarios.
- `tests.bundle`: the data path (`prepare`/`verify-bundle`) and opt-in stage reuse.
- `tests.parserLibrary`: the in-process parser library: one process with all
  grammars, and, on Linux, the sanitizer job over every parser test input and
  corpus text. Its runtime root holds the built library and inputs, so a model,
  harness or documentation change reuses the result.

`just test-scheduled` builds the scheduled suites of `tests/nix_scheduled_suites.json`
with `nix-build -A scheduledTests`. `just package` runs it, so main pushes, tags,
manual and nightly runs check these suites, and so does a pull request with the
`package` scope. Pull requests with a smaller scope do not, so that their CI time
does not grow. The flake checks exclude them.

- `scheduledTests.writers`: round trips of the corpus writers of the authored cases
  (`conformance/*_evidence.py`): each writes a new corpus, reads it back unchanged
  and replays it natively. The corpora they wrote are frozen, and `tests.frozen` and
  the verdict check them on every pull request.

Each target runs ordinary pytest on a cache miss. Its explicit source files,
Python/pytest, native tools, Lean artifacts and command determine its Nix identity.
Successful outputs retain pytest's JUnit XML. There is no Python cache validator or
coverage-report gate. Nix sandboxing is enabled, with fallback disabled.

Each target declares only the inputs that its tests read. The conformance targets
(`model`, `frozen`, `harness`, `sample` and `upstream`) receive only the SQL frontend
modules listed in `tests/conformance_frontend.json`, so a change to the verification
application, for example `migration_check/prepare.py`, keeps their results.
`tests/test_conformance_frontend.py` checks that list against the actual imports.
Only `tests.frozen` (and the `corpora`, `sample` and `upstream` targets that read them) depend on
the large frozen corpora and retained reports.

The `bundle` target runs `prepare` and `verify-bundle`, which build with Lake and
its artifact cache ([ADR 0010](adr-0010-lake-builds-and-artifact-cache.md)). Its
cache starts from the case seeds (`build-support/case-seeds.nix`): one Nix derivation
for each folder with a `belay.toml`, whose output is the Lake cache after preparing
and verifying that case. A test that runs a case unchanged compiles nothing; a test
that needs a cold cache passes `--cache` itself. The seeds build with a runtime
that has no `examples/` folder, so a change to one case rebuilds only its seed. `just test-cases` keeps one cache under `build/lake-test-cache`.

While ADR 0010 is implemented, each pull request records its CI job times next to
the latest comparable `main` run, and a big increase (starting threshold: 20 % or
2 minutes for a job) is explained before the merge (ADR 0010 section 11).

The frozen corpora (v1 to v9 and the synthetic workload corpus) are the corpora
that `judge/claims.json` claims, and the judge lock protects their bytes
(ADR 0011, "Verdict of the development claims" below).
`conformance.corpus.load` decodes a locked corpus without validating it again.
Any other directory, such as a copy, a capture or a new freeze, gets the
complete validation (`conformance.corpus.validated_load`). `tests.corpora`
(`tests/conformance_locked_corpora_test.py`) runs the complete validation on
each locked corpus. Its inputs are only the claims, the corpora, the SQL
frontend and the conformance modules that the validation imports, so it runs
again when a corpus changes, which is in the pull request that changes the
judge lock. A module missing from its input list fails it with an import error.

Each test has a 300-second limit (`pytest-timeout`), so a hung test fails with its
own name. Nix runs several targets at the same time, so a target's total time
depends on the other targets; its 1200-second limit only guards against a hang
outside a test.

The remaining cheap source cases run in one pytest invocation. Cases marked
`requires_nix` (source identities, test-target commands, environment snapshots,
installer cache paths) run in `just test-nix`; CI selects it for changes to build
definitions and shared test infrastructure. `just test-atuin` selects
only the cached Atuin target. Tests use trusted repository fixtures; no production
sandbox is supplied or tested. Nix daemon and installation tests run on the host.
Cheap unit tests rerun normally. Direct `just test-cases FILE` always executes
pytest, even if the corresponding Nix target is already cached.
Development `just test` selects `developmentTests`, the same targets except
`tests.model`, `tests.frozen`, `tests.corpora` and `tests.mutants`. `tests/nix_suites.json` assigns test files to Nix and supplies the
host `--source-checks` exclusion list. Source-owned conformance checks remain
fresh. Every scope from `test` up runs all Nix targets of `tests`.

The pinned cache-nix-action restores the Nix store on every applicable run.
Only main pushes and nightly runs save caches after their checks. The cache key is the platform, the Nix pins and a hash of
every file except `plans/` and `reviews/`. A push that changes only task records
therefore restores the exact store of the earlier push, finds every Nix target
cached and saves nothing. Other runs restore the newest visible matching store for their platform and pins.
Pull requests, tags and manual runs do not save caches. Nix, not the GitHub cache
key, determines which outputs can be reused; changing a declared input creates a
different test derivation.

The check job also substitutes from the publicly readable Vihren Attic cache,
`https://cache.vihren.dev/sqlite-verifier`, trusting only its signing key
`sqlite-verifier:XgeRqTIGBEw3VP8GPrzSvdU+5t1lJz7uEMhIG1lh7QE=` in addition to
cache.nixos.org. Reads need no credentials, so fork pull requests use it too.
`connect-timeout = 5` and `fallback = true` make an unreachable cache or a failed
download fall back to a local build; substitution fallback is unrelated to
`sandbox-fallback`, which stays disabled.

After both native checks of a `main` push or nightly run pass, the
`publish-nix-store` job restores, per platform, exactly the store that the check
job saved and uploads its paths with the pinned Attic client; Attic skips paths
that cache.nixos.org already provides. Only that job uses the `attic-publish`
environment, which deploys only from `main` and holds `ATTIC_WRITE_TOKEN`; pull
request, tag and manual jobs never receive the token. The job may fail or reach
its 60-minute limit without failing the workflow, and it changes no check
result. A missing saved store uploads nothing. The cache, its token rotation and
server operation are maintained in the devops repository
(`docs/vihren-demo/attic-ops.md`). An earlier attempt uploaded inside the check
job and was rolled back ([record](../plans/20260929-attic-ci.status.md)).

Before the save, `tools/ci_store_gc.py` registers garbage-collector roots for the
test targets, runtimes, base API reference (`apiReferenceBase`),
development shell and flake inputs of the current commit, and removes every other
store path. The base API reference and its doc-gen4 build input add about 53 MB
compressed for each platform. Nix keeps the outputs of rooted
derivations' build inputs (`keep-outputs`). Without this step the store kept every
older commit's outputs and grew to 5.8 GB for Linux, while one commit needs about
1.4 GB compressed; GitHub keeps at most 10 GB of caches for a repository, so the
platform caches evicted each other. A path removed by mistake costs a rebuild in a
later run and cannot change a result. The step may fail without failing the job.

Host JUnit reports, cached Nix test outputs and CI phase diagnostics are
retained for 14 days. Pytest's exit status decides success. Individual subprocess
and whole-command deadlines remain bounded (a timed-out test command's process
group is killed). The hosted job limit is 75 minutes, including the reference phase, runtime,
Darwin bundle, complete checks, setup and artifact retention. Child limits
are individual upper bounds; their sum is not a promised job duration. Individual suite and command limits remain unchanged.
Superseded ordinary runs are cancelled; release/manual runs are not.

The matrix follows GitHub's documented native runner architectures:
`ubuntu-22.04` is x64 (`x86_64-linux`), and `macos-14` is Apple Silicon
(`aarch64-darwin`). Each job also checks Nix's actual host system before building.
See [GitHub's hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
Runner image updates remain controlled by GitHub; project dependencies are pinned
separately in `nix/flake.lock` and `lean-toolchain`.

Action commits were resolved from official repository tag references on
2026-09-24: `actions/checkout` v6, `cachix/install-nix-action` v31 (an annotated
tag, dereferenced to its commit), and `actions/upload-artifact` v4. The workflow
pins the full commits rather than floating tags. Checkout does not persist
credentials, and the workflow requests read-only repository content permission.

Successful packaging jobs retain development-source snapshots and checked native
runtime archives for 14 days; ordinary checks do not create these archives.
Runtime
acceptance installs into a fresh directory with spaces, Unicode and URI-special
characters, and checks both parsers, the positive, refuted and unsupported examples,
the installed dependency roots, and the Atuin cases under
a controlled environment without elan or ambient Python imports. The Nix local
cache retains the complete content-addressed runtime closure with import
verification enabled. Execution isolation is the caller’s responsibility.

Pushes of `v*` tags run the same two-platform checks. Only after both pass does the
release job download their artifacts, verify the archive checksums, and create a
GitHub Release. The publishing job alone has write permission. No existing release
is overwritten. The download-artifact v5 commit was resolved from the official
repository tag on 2026-09-24. Tag creation remains a coordinated release action.
A passing engineering workflow does not mean roadmap Step 1 is complete.

The main ruleset requires `Check (x86_64-linux)` and `Check (aarch64-darwin)`
and requires a branch to be up to date before it merges. Changes to approved
example requirements are ordinary test-fixture changes and get the same
review as other changes.

## Verdict of the development claims

The `Verdict` workflow (`.github/workflows/verdict.yml`) runs on every pull
request, including documentation-only ones (ADR 0011). It becomes a required
check of ruleset 23934665 when the owner adds it there after this workflow is
on `main`. It runs
`nix-build integrity/judge.nix -A verdict` and nothing else on its host, and it
restores no GitHub Actions cache.

`integrity/judge.nix` first compares each part of the judge with
`integrity/judge.lock.json`: the judge code and `judge/claims.json`, each claimed
corpus, and the native SQLite oracle (`nix/sqlite.nix` with `nix/flake.lock`).
A changed part stops the job with its name. Then three Nix builds run: the judge
writes the subject's inputs, the subject (`conformance.predict`) predicts from
those inputs in a build without the corpora, and the judge checks the claims.
`verdict-report` keeps the counts and every verdict for 14 days.

`just verdict` builds the same verdict locally. `just judge-lock` prints the
current lock values. A change to the judge, the claims, a corpus or the oracle
updates `integrity/judge.lock.json` in its own pull request, which the owner
approves; `.github/CODEOWNERS` lists the lock, `integrity/judge.nix` and the
workflows.

## Maintainer release

From the primary checkout, after reviewed `main` CI is green and release notes
are current, choose an unused version tag that starts with `v`. Use a hyphen
in the version for a prerelease. Replace `VERSION` in these commands with that tag:

```sh
jj tag set VERSION -r main
git push origin refs/tags/VERSION
```

The installed Jujutsu supports tag creation, but its push command transports
bookmarks; Git is used for this tag-only push. The tag workflow reruns both
platform checks and marks hyphenated version tags as prereleases. Watch that run
and verify both published archives and checksum files before announcing it.
Never move or reuse a released or failed release tag; use a fresh version after
a fix. The owner accepted the Step 1 product on 2026-09-25. Stable v0.1.1 was
published on 2026-09-28 after both complete platform jobs passed twice at `7a99c71f`;
published checksum files match the archive asset digests. The failed v0.1.0 tag
remains unchanged, and v0.1.0-rc.1 is an earlier engineering preview.

Stable [v0.1.2](https://github.com/vihren-dev/sqlite-verifier/releases/tag/v0.1.2)
was published on 2026-10-07 from reviewed merge `bc9e2dce`. Both native package
jobs and checksum-verified publication passed in workflow `37591468199`.
Its public checksum files match the uploaded archive asset digests. The
[release record](../reports/20261007-lean-4341-release/README.md) retains the
asset identities and verification scope. This tag remains unchanged.

The manually dispatched `ADR 0003 P1 measurement` workflow
(`.github/workflows/adr3-p1.yml`) runs the latency matrix on Linux and uploads its
results; it gates nothing. See the
[P1](../experiments/adr-0003-latency/p1-results.md) and
[P2](../experiments/adr-0003-latency/p2-results.md) results.

The [native benchmark protocol](adr1-benchmarks.md) records the earlier isolated
60-job comparison. Its workflows and tools were removed on 2026-09-29.
