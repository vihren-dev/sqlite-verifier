#!/usr/bin/env bash
set -eu
source_dir=$1
cd "$source_dir"
mkdir -p build/test-results
sha256sum --check ../source.sha256 > ../source-before.log
test "$(readlink CLAUDE.md)" = AGENTS.md
nix develop path:./nix --command sh -c '
  timeout 900 nix-build build-support/default.nix -A conformance --out-link build/conformance --extra-experimental-features "nix-command flakes" > build/t05-mutation-conformance-build.log 2>&1
'
nix develop path:./nix --command sh -c '
  timeout --foreground 420 python3 -m pytest "tests/conformance_generation_test.py::test_stateful_modes[True]" tests/test_mutation_source.py --runtime-root build/conformance -v --junitxml build/test-results/t05-mutation-targeted.xml > build/t05-mutation-targeted.log 2>&1
'
nix develop path:./nix --command sh -c '
  timeout 900 nix-build build-support/default.nix -A tests.model --out-link build/t05-nix-model --option sandbox true --option sandbox-fallback false --extra-experimental-features "nix-command flakes" > build/t05-model-full-linux.log 2>&1
'
sha256sum --check ../source.sha256 > ../source-after.log
test "$(readlink CLAUDE.md)" = AGENTS.md
printf '%s\n' T05_FULL_MODEL_COMPLETE
