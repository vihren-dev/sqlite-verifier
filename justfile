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

# Extended formal/conformance suites are added by their owning changes.
test: smoke

check: build test

# A development source snapshot; installable verifier artifacts follow the CLI.
package: check
    mkdir -p dist
    tar --exclude='./.jj' --exclude='./.git' --exclude='./.lake' --exclude='./.direnv' --exclude='./dist' --exclude='./result*' -czf dist/sqlite-verifier-source.tar.gz .
