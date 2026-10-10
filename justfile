# Shared entry points. Enter nix develop path:./nix once for a batch of checks.
default:
    @just --list

# Resource checks never delete caches or user data.
resources:
    python3 tools/check_resources.py

# Prepare the pinned runtime through the same Nix build used by tests and releases.
setup: build

# Build the complete runtime and expose the existing development paths.
build: resources
    mkdir -p build .lake
    timeout 900 nix-build build-support/default.nix -A runtime --out-link build/runtime --extra-experimental-features 'nix-command flakes'
    rm -rf .lake/build packages/belay-sqlite/.lake/build
    mkdir -p packages/belay-sqlite/.lake
    ln -sfn ../build/runtime/.lake/build .lake/build
    ln -sfn ../../../build/runtime/packages/belay-sqlite/.lake/build packages/belay-sqlite/.lake/build
    ln -sfn build/runtime/lean lean
    ln -sfn build/runtime/lib lib

# Run an explicitly selected scenario without rebuilding its prerequisites.
[positional-arguments]
test-cases *args:
    python3 -m pytest --runtime-root "${SQLITE_VERIFIER_RUNTIME_ROOT:-$PWD}" "$@"

# Build the test-only compiled model without adding commands to the shipped runtime.
conformance-build:
    mkdir -p build
    timeout 900 nix-build build-support/default.nix -A conformance --out-link build/conformance --extra-experimental-features 'nix-command flakes'

# Build the checked library reference from an exact source commit, without hosting it.
[positional-arguments]
reference revision: resources
    mkdir -p build
    timeout 1800 nix-build build-support/default.nix -A apiReference --argstr referenceRevision "$1" --out-link build/api-reference --option sandbox true --option sandbox-fallback false --extra-experimental-features 'nix-command flakes'

# Record live prototype evidence; W3 remains an owner decision after reviewing it.
[positional-arguments]
conformance *args: conformance-build
    timeout 420 python3 -m conformance.pipeline --runtime-root build/conformance --output build/conformance-evidence "$@"

# List selected scenarios without building or executing fixtures.
[positional-arguments]
test-list *args:
    python3 -m pytest --collect-only -q "$@"

# Check pinned tools through the same scenario interface.
smoke:
    timeout --foreground 15 python3 -m pytest tests/test_toolchain_smoke.py --runtime-root "${SQLITE_VERIFIER_RUNTIME_ROOT:-$PWD}"

# Fresh development replay includes every authored/synthetic case and a stable upstream sample.
test: build documentation-inventory test-source
    timeout 900 nix-build build-support/default.nix -A developmentTests --out-link build/nix-tests --option sandbox true --option sandbox-fallback false --extra-experimental-features 'nix-command flakes'

# CI and package checks retain all full model, kernel and historical evidence checks.
test-full: build documentation-inventory test-source
    timeout 900 nix-build build-support/default.nix -A tests --out-link build/nix-tests-full --option sandbox true --option sandbox-fallback false --extra-experimental-features 'nix-command flakes'

# Check every authored public declaration, constructor and field in the compiled import closure.
documentation-inventory: resources
    mkdir -p build
    timeout 900 nix-build build-support/default.nix -A publicDocumentation --out-link build/public-documentation --option sandbox true --option sandbox-fallback false --extra-experimental-features 'nix-command flakes'

# Test ownership is shared with Nix; all source-owned checks run on the host.
test-source:
    timeout --foreground 600 python3 -u -m pytest -v tests -m "not requires_nix" --source-checks --runtime-root "${SQLITE_VERIFIER_RUNTIME_ROOT:-$PWD}" --junitxml build/test-results/source.xml

# Review a commit (default: @-) with the other agent tool against docs/review-checklist.md (REVIEWER= overrides).
[positional-arguments]
review *args:
    python3 -m tools.review "$@"

# Record what happened to one review finding: fixed, rejected REASON, or deferred REASON.
[positional-arguments]
review-resolve *args:
    python3 -m tools.review_log "$@"

# Report per checklist condition how often it fired and what happened to its findings.
[positional-arguments]
review-stats *args:
    python3 -m tools.review_stats "$@"

# Check Nix source identities, test-target invalidation, environment snapshots and the installer cache.
test-nix:
    timeout --foreground 600 python3 -u -m pytest -v tests -m requires_nix --ignore=tests/runtime_package_test.py --runtime-root "${SQLITE_VERIFIER_RUNTIME_ROOT:-$PWD}" --junitxml build/test-results/nix.xml

# Select only the cached application-specific suite.
test-atuin:
    mkdir -p build
    timeout 900 nix-build build-support/default.nix -A tests.atuin --out-link build/nix-atuin --option sandbox true --option sandbox-fallback false --extra-experimental-features 'nix-command flakes'

# Build a native offline archive and verify its actual installed entrypoint.
runtime-package: build
    timeout 1200 python3 packaging/build_runtime.py --runtime-root "${SQLITE_VERIFIER_RUNTIME_ROOT:-$PWD/build/runtime}"
    timeout --foreground 1800 python3 -m pytest --junitxml build/test-results/installed.xml --runtime-archive "dist/sqlite-verifier-${SQLITE_VERIFIER_SYSTEM:?Enter nix develop path:./nix}.tar.gz" --runtime-variant installed tests/runtime_package_test.py tests/atuin_cli_test.py

# Keep a source snapshot alongside the checked installable runtime.
package: test-full test-nix runtime-package
    mkdir -p dist
    tar --exclude='./.jj' --exclude='./.git' --exclude='./.lake' --exclude='./.direnv' --exclude='./dist' --exclude='./build' --exclude='__pycache__' --exclude='./result*' -czf dist/sqlite-verifier-source.tar.gz .

# Refresh into build/, then review and assign a new corpus version before freezing.
conformance-upstream: conformance-build
    timeout 900 nix-build build-support/default.nix -A conformanceNative.fixture --out-link build/testfixture --extra-experimental-features 'nix-command flakes'
    timeout 900 nix-build build-support/default.nix -A conformanceNative.upstream --out-link build/upstream-sqlite --extra-experimental-features 'nix-command flakes'
    timeout 900 python3 -m conformance.upstream_pilot --fixture build/testfixture/bin/testfixture --upstream build/upstream-sqlite --output build/upstream-pilot --pattern 'alter*.test' --pattern 'e_*.test'

# Select native fixture storage explicitly; Linux full replay can opt in to tmpfs.
conformance-corpus temporary_root: conformance-build
    timeout 420 python3 -m conformance.corpus conformance/corpus-v5 --runtime-root build/conformance --native-check --temporary-root {{quote(temporary_root)}} --output build/corpus-progress.json

# The transaction/DML profiling gate is recorded in the W3/W4 status and reports.
conformance-generate: conformance-build
    timeout 120 python3 -m conformance.generate

conformance-mutations: conformance-generate
    timeout 180 python3 -m conformance.mutation_check build/generated/cases.jsonl --output build/generated/mutations.json

conformance-long: conformance-build
    timeout 600 python3 -m conformance.generate --examples 500 --steps 25 --output build/generated-long

# Versioned requirement extraction uses the vendored, release-tagged docsrc archive.
conformance-requirements:
    timeout 900 nix-build build-support/default.nix -A conformanceDocs --out-link build/conformance-docs --extra-experimental-features 'nix-command flakes'
    python3 -m conformance.requirement_inventory build/conformance-docs/docinfo.db build/requirements-3.51.0.json

# Classify every frozen case without performing fresh native replay.
conformance-progress: conformance-build
    timeout 420 python3 -m conformance.progress --runtime-root build/conformance --output build/corpus-v5-progress.json

# Supply llvm-cov's executable path and a fresh output directory for each measurement.
conformance-coverage llvm_cov output: conformance-generate
    timeout 900 nix-build build-support/default.nix -A conformanceCoverage --out-link build/model-coverage --extra-experimental-features 'nix-command flakes'
    timeout 900 nix-build build-support/default.nix -A conformanceNative.coverage --out-link build/native-coverage --extra-experimental-features 'nix-command flakes'
    timeout 300 python3 -m conformance.measure_coverage --llvm-cov {{quote(llvm_cov)}} --output {{quote(output)}}
