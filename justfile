# Shared entry points for development and CI. Run inside nix develop.
default:
    @just --list

# Elan reads the exact release from lean-toolchain.
setup:
    timeout 300 elan toolchain install "$(cat lean-toolchain)"

# Compile the public proof library entry point.
build:
    timeout 120 lake build

# Check pinned tools, and exercise the native engine independently of the model.
smoke:
    timeout 15 python3 tests/toolchain_smoke.py

# Run real process-isolation checks and the independently expected native smoke.
test: smoke
    timeout 30 python3 -m unittest discover -s tests -p 'test_*.py'

check: build test

# A development source snapshot; installable verifier artifacts follow the CLI.
package: check
    mkdir -p dist
    tar --exclude='./.jj' --exclude='./.git' --exclude='./.lake' --exclude='./.direnv' --exclude='./dist' --exclude='./result*' -czf dist/sqlite-verifier-source.tar.gz .
