# Shared entry points for development and CI. Run inside nix develop.
default:
    @just --list

# Elan reads the exact release from lean-toolchain.
setup:
    timeout 300 elan toolchain install "$(cat lean-toolchain)"

# Compile the public proof library entry point.
build: parser
    timeout 120 lake build SqliteVerifier migration-proof-checker

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
    timeout 180 python3 tests/kernel_gate_test.py
    timeout 180 python3 -m tests.compilation_test
    timeout 600 python3 tests/cli_test.py
    timeout 30 python3 -m unittest discover -s tests -p 'test_*.py'

check: build test

# A development source snapshot; installable verifier artifacts follow the CLI.
package: check
    mkdir -p dist
    tar --exclude='./.jj' --exclude='./.git' --exclude='./.lake' --exclude='./.direnv' --exclude='./dist' --exclude='./build' --exclude='__pycache__' --exclude='./result*' -czf dist/sqlite-verifier-source.tar.gz .
