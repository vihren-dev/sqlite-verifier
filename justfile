# Shared entry points. Enter nix develop path:./nix#capture once for full checks.
default:
    @just --list

# Resource checks never delete caches or user data.
resources:
    python3 tools/check_resources.py

# Full verification uses the pinned Rust tools without a nested environment entry.
capture-shell:
    python3 tools/check_resources.py --environment-only --capture

# Elan reads the exact release from lean-toolchain.
setup: resources
    timeout 300 elan toolchain install "$(cat lean-toolchain)"

# Compile the public proof library entry point.
build: parser
    timeout 120 lake build SqliteVerifier migration-proof-checker
    timeout 30 python3 packaging/write_runtime_roots.py

# Compile the pinned complete SQLite grammar and tokenizer.
parser: resources
    timeout 120 python3 parser/build.py

# Check pinned tools, and exercise the native engine independently of the model.
smoke:
    timeout 15 python3 tests/toolchain_smoke.py

# Run real process-isolation checks and the independently expected native smoke.
test: smoke
    timeout 150 python3 tests/environment_snapshot_test.py
    timeout 30 python3 tests/parser_test.py
    timeout 75 python3 tests/schema_generation_test.py
    timeout 20 python3 tests/conformance_native_test.py
    timeout 180 python3 tests/conformance_model_test.py
    timeout 180 python3 tests/conformance_atuin_model_test.py
    timeout 360 python3 tests/kernel_gate_test.py
    timeout 180 python3 -m tests.compilation_test
    timeout 600 python3 tests/cli_test.py
    timeout 1500 python3 tests/atuin_cli_test.py
    timeout 15 python3 tests/coverage_test.py
    timeout 30 python3 -m unittest discover -s tests -p 'test_*.py'

# Refresh bounded proof, grammar and native/model evidence.
coverage: build
    timeout 420 python3 conformance/coverage_report.py --output build/coverage.json

check: capture-shell build atuin-native test coverage

# Reproduce the real SQLx runner using its separately pinned build environment.
atuin-native: capture-shell resources
    env CARGO_HOME="${CARGO_HOME:-$PWD/build/atuin-cargo-home}" CARGO_TARGET_DIR="$PWD/build/atuin-cargo-target" timeout 600 cargo build --locked --manifest-path conformance/atuin_capture/Cargo.toml
    timeout 45 python3 -m unittest tests.atuin_capture_test tests.atuin_runner_test

# Build a native offline archive and verify its actual installed entrypoint.
runtime-package: resources
    timeout 600 python3 packaging/build_runtime.py
    timeout 600 python3 tests/runtime_package_test.py "dist/sqlite-verifier-${SQLITE_VERIFIER_SYSTEM:?Enter nix develop path:./nix#capture}.tar.gz"

# Keep a source snapshot alongside the checked installable runtime.
package: check runtime-package
    mkdir -p dist
    tar --exclude='./.jj' --exclude='./.git' --exclude='./.lake' --exclude='./.direnv' --exclude='./dist' --exclude='./build' --exclude='__pycache__' --exclude='./result*' -czf dist/sqlite-verifier-source.tar.gz .
