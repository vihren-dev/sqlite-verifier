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
    timeout --foreground 600 python3 -u -m pytest -v tests -m "not requires_nix" --ignore=tests/runtime_package_test.py --ignore=tests/kernel_gate_test.py --ignore=tests/conformance_model_test.py --ignore=tests/atuin_cli_test.py --ignore=tests/cli_test.py --ignore=tests/bundle_test.py --ignore=tests/stage_reuse_test.py --runtime-root "${SQLITE_VERIFIER_RUNTIME_ROOT:-$PWD}" --junitxml build/test-results/source.xml

# Explicit live cache check; requires ATTIC_READ_TOKEN and ATTIC_WRITE_TOKEN.
test-attic:
    timeout 180 bash tools/check_attic.sh

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
