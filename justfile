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
    rm -rf .lake/build build/parser build/parser-3.46.0
    ln -sfn ../build/runtime/.lake/build .lake/build
    ln -sfn build/runtime/lean lean
    for name in parser parser-3.46.0 sqlite-parser sqlite-parser-3.46.0; do ln -sfn "runtime/build/$name" "build/$name"; done

# Compile the pinned complete SQLite grammar and tokenizer.
parser: resources
    mkdir -p build
    timeout 300 nix-build build-support/default.nix -A parsers --out-link build/parsers --extra-experimental-features 'nix-command flakes'
    rm -rf build/parser build/parser-3.46.0
    for name in parser parser-3.46.0 sqlite-parser sqlite-parser-3.46.0; do ln -sfn "parsers/build/$name" "build/$name"; done

# Run an explicitly selected scenario without rebuilding its prerequisites.
[positional-arguments]
test-cases *args:
    python3 -m pytest --runtime-root "${SQLITE_VERIFIER_RUNTIME_ROOT:-$PWD}" "$@"

# Build the test-only compiled model without adding commands to the shipped runtime.
conformance-build:
    mkdir -p build
    timeout 900 nix-build build-support/default.nix -A conformance --out-link build/conformance --extra-experimental-features 'nix-command flakes'

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

# Cache expensive hermetic suites in Nix; run cheap source tests on the host.
# The same derivations are the flake's checks; nix-build also keeps result links.
test: build
    timeout 900 nix-build build-support/default.nix -A tests --out-link build/nix-tests --option sandbox true --option sandbox-fallback false --extra-experimental-features 'nix-command flakes'
    timeout --foreground 600 python3 -u -m pytest -v tests -m "not requires_nix" --ignore=tests/runtime_package_test.py --ignore=tests/kernel_gate_test.py --ignore=tests/conformance_model_test.py --ignore=tests/conformance_trace_test.py --ignore=tests/conformance_pipeline_test.py --ignore=tests/conformance_mutation_test.py --ignore=tests/conformance_laws_test.py --ignore=tests/conformance_record_test.py --ignore=tests/conformance_dqs_test.py --ignore=tests/conformance_upstream_test.py --ignore=tests/conformance_generation_test.py --ignore=tests/atuin_cli_test.py --ignore=tests/cli_test.py --runtime-root "${SQLITE_VERIFIER_RUNTIME_ROOT:-$PWD}" --junitxml build/test-results/source.xml

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
package: test test-nix runtime-package
    mkdir -p dist
    tar --exclude='./.jj' --exclude='./.git' --exclude='./.lake' --exclude='./.direnv' --exclude='./dist' --exclude='./build' --exclude='__pycache__' --exclude='./result*' -czf dist/sqlite-verifier-source.tar.gz .

# Refresh into build/, then review and assign a new corpus version before freezing.
conformance-upstream: conformance-build
    timeout 900 nix-build build-support/default.nix -A conformanceNative.fixture --out-link build/testfixture --extra-experimental-features 'nix-command flakes'
    timeout 900 nix-build build-support/default.nix -A conformanceNative.upstream --out-link build/upstream-sqlite --extra-experimental-features 'nix-command flakes'
    timeout 900 python3 -m conformance.upstream_pilot --fixture build/testfixture/bin/testfixture --upstream build/upstream-sqlite --output build/upstream-pilot

conformance-corpus: conformance-build
    timeout 420 python3 -m conformance.corpus conformance/corpus-v1 --native-check --output build/corpus-progress.json

# The transaction/DML profiling gate is recorded in the W3/W4 status and reports.
conformance-generate: conformance-build
    timeout 120 python3 -m conformance.generate

conformance-long: conformance-build
    timeout 600 python3 -m conformance.generate --examples 500 --steps 25 --output build/generated-long
