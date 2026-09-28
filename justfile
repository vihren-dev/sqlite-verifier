# Shared entry points. Enter nix develop path:./nix once for a batch of checks.
default:
    @just --list

# Resource checks never delete caches or user data.
resources:
    python3 tools/check_resources.py

# Elan reads the exact release from lean-toolchain.
setup: resources
    timeout 300 elan toolchain install "$(cat lean-toolchain)"

# Prepare Nix parsers; an explicit Nix runtime supplies Lean outputs.
build: parser
    if [ -z "${SQLITE_VERIFIER_RUNTIME_ROOT:-}" ]; then timeout 120 lake build SqliteVerifier migration-proof-checker && timeout 30 python3 packaging/write_runtime_roots.py; fi

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

# Catalogue selected scenarios without building or executing fixtures.
[positional-arguments]
test-list *args:
    python3 -m pytest --catalog "$@"

# Check pinned tools through the same scenario interface.
smoke:
    python3 -m tools.run_independent_suites --timeout 15 --suite smoke --runtime-root "${SQLITE_VERIFIER_RUNTIME_ROOT:-$PWD}" -- tests/test_toolchain_smoke.py

# Execute source cases once, then aggregate only this invocation's fresh evidence.
test: build
    python3 -m tools.run_source_suite

# Build a native offline archive and verify its actual installed entrypoint.
runtime-package: resources
    timeout 600 python3 packaging/build_runtime.py --python "${SQLITE_VERIFIER_PYTHON:?Enter nix develop path:./nix}" --runtime-root "${SQLITE_VERIFIER_RUNTIME_ROOT:-$PWD}"
    python3 -m tools.run_independent_suites --timeout 1800 --suite installed --runtime-archive "dist/sqlite-verifier-${SQLITE_VERIFIER_SYSTEM:?Enter nix develop path:./nix}.tar.gz" --runtime-variant installed -- tests/runtime_package_test.py tests/atuin_cli_test.py

# Keep a source snapshot alongside the checked installable runtime.
package: test runtime-package
    mkdir -p dist
    tar --exclude='./.jj' --exclude='./.git' --exclude='./.lake' --exclude='./.direnv' --exclude='./dist' --exclude='./build' --exclude='__pycache__' --exclude='./result*' -czf dist/sqlite-verifier-source.tar.gz .
