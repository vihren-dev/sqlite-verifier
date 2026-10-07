#!/usr/bin/env bash
# Validate public tracked T05 source in a fresh Linux task directory; no full model or benchmark.
set -eu
t05_source_directory="$1"
cd "$t05_source_directory"
mkdir -p build/test-results
nix develop "path:$t05_source_directory/nix" --command bash -s <<'CHECKS'
set -eu
timeout 900 just build > build/linux-build.log 2>&1
readlink -f build/runtime > build/linux-runtime-path.txt
export SQLITE_VERIFIER_RUNTIME_ROOT="$PWD/build/runtime"
timeout 600 just test-source > build/linux-source.log 2>&1
timeout 900 nix-build build-support/default.nix -A developmentTests --out-link build/linux-tests \
  --option sandbox true --option sandbox-fallback false \
  --extra-experimental-features 'nix-command flakes' > build/linux-tests.log 2>&1
timeout 600 just test-nix > build/linux-nix.log 2>&1
timeout 120 nix-build build-support/default.nix -A conformance --out-link build/linux-conformance \
  --extra-experimental-features 'nix-command flakes' > build/linux-conformance-build.log 2>&1
timeout 120 python3 -m pytest -v tests/conformance_model_test.py tests/conformance_laws_test.py \
  --runtime-root build/linux-conformance --junitxml build/test-results/linux-model-short.xml \
  > build/linux-model-short.log 2>&1
timeout 1200 python3 packaging/build_runtime.py --runtime-root build/runtime \
  --output-dir build/linux-archive > build/linux-package.log 2>&1
timeout 1800 python3 -m pytest -v --runtime-archive build/linux-archive/sqlite-verifier-x86_64-linux.tar.gz \
  --runtime-variant installed tests/runtime_package_test.py tests/atuin_cli_test.py \
  tests/proof_exporter_test.py tests/single_executor_test.py \
  --junitxml build/test-results/linux-installed.xml > build/linux-installed.log 2>&1
CHECKS
