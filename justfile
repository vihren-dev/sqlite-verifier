# Shared entry points for development and CI. Run inside nix develop.
default:
    @just --list

# Elan reads the exact release from lean-toolchain.
setup:
    timeout 300 elan toolchain install "$(cat lean-toolchain)"

# Compile the public proof library entry point.
build: parser
    timeout 120 lake build SqliteVerifier migration-proof-checker
    timeout 30 python3 packaging/write_runtime_roots.py

# Compile the pinned complete SQLite grammar and tokenizer.
parser:
    timeout 120 python3 parser/build.py

# Check pinned tools, and exercise the native engine independently of the model.
smoke:
    timeout 15 python3 tests/toolchain_smoke.py

# Run real process-isolation checks and the independently expected native smoke.
test: smoke
    timeout 30 python3 tests/parser_test.py
    timeout 20 python3 tests/conformance_native_test.py
    timeout 180 python3 tests/conformance_model_test.py
    timeout 360 python3 tests/kernel_gate_test.py
    timeout 180 python3 -m tests.compilation_test
    timeout 600 python3 tests/cli_test.py
    timeout 15 python3 tests/coverage_test.py
    timeout 30 python3 -m unittest discover -s tests -p 'test_*.py'

# Refresh bounded proof, grammar and native/model evidence.
coverage: build
    timeout 420 python3 conformance/coverage_report.py --output build/coverage.json

check: build test coverage

# Reproduce the real SQLx runner; run this entry point inside nix develop .#capture.
atuin-native:
    CARGO_HOME="${CARGO_HOME:-$PWD/build/atuin-cargo-home}" CARGO_TARGET_DIR="$PWD/build/atuin-cargo-target" timeout 600 cargo build --locked --manifest-path conformance/atuin_capture/Cargo.toml
    timeout 45 python3 -m unittest discover -s tests -p 'atuin_*test.py'

# Build a native offline archive and verify its actual installed entrypoint.
runtime-package:
    timeout 600 python3 packaging/build_runtime.py
    timeout 600 python3 tests/runtime_package_test.py "dist/sqlite-verifier-$(nix eval --impure --raw --expr builtins.currentSystem).tar.gz"

# Keep a source snapshot alongside the checked installable runtime.
package: check runtime-package
    mkdir -p dist
    tar --exclude='./.jj' --exclude='./.git' --exclude='./.lake' --exclude='./.direnv' --exclude='./dist' --exclude='./build' --exclude='__pycache__' --exclude='./result*' -czf dist/sqlite-verifier-source.tar.gz .
