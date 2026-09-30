#!/usr/bin/env bash
# ADR 0003 latency experiment: export each example's proof closure with lean4export v4.33.0
# and time checking strategies. Run inside `nix develop path:./nix` after `just build`.
# Usage: experiments/adr-0003-latency/run_data_path.sh [TRIALS]
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
WORK=$ROOT/build/adr-0003-latency
TRIALS=${1:-2}
LEAN=$ROOT/lean
LIBRARY=$ROOT/.lake/build/lib/lean
EXPORTER_REV=15f6055e299ad5b89345e533cc2192f4cc00f659 # lean4export tag v4.33.0
export PATH="$LEAN/bin:$PATH" LEAN_SYSROOT="$LEAN"

now() { python3 -c 'import time; print(time.perf_counter())'; }
elapsed() { python3 -c "print(round($2 - $1, 2))"; }

mkdir -p "$WORK/exports"
python3 "$HERE/prepare_examples.py" > /dev/null

if [ ! -d "$WORK/lean4export" ]; then
  git clone -q https://github.com/leanprover/lean4export "$WORK/lean4export"
  git -C "$WORK/lean4export" checkout -q "$EXPORTER_REV"
  git -C "$WORK/lean4export" apply "$HERE/lean4export-skip-trusted.patch"
fi
(cd "$WORK/lean4export" && lake build lean4export > /dev/null)
rm -rf "$WORK/bench" && cp -R "$HERE/bench" "$WORK/bench"
(cd "$WORK/bench" && lake build > /dev/null)
EXPORTER=$WORK/lean4export/.lake/build/bin/lean4export
BENCH=$WORK/bench/.lake/build/bin/bench

targets=(Generated.startSchema Generated.nextSchema Generated.script Generated.profile Requirements.contract
  Requirements.LogicalState Interpretation.admitted Interpretation.current NextInterpretation.next
  NextInterpretation.failures SqliteVerifier.VerificationConditions)

for case in small refutation atuin; do
  theorem=Proofs.migrationCorrect; [ "$case" = refutation ] && theorem=Proofs.migrationViolated
  export LEAN_PATH="$LEAN/lib/lean:$LIBRARY:$WORK/compiled/$case/trusted:$WORK/compiled/$case/candidate"
  for variant in full filtered; do
    options=(); [ "$variant" = filtered ] && options=(--skip-trusted)
    output=$WORK/exports/$case-$variant.ndjson
    for trial in $(seq "$TRIALS"); do
      start=$(now)
      "$EXPORTER" "${options[@]}" Proofs -- "$theorem" "${targets[@]}" > "$output"
      echo "$case export-$variant trial=$trial seconds=$(elapsed "$start" "$(now)") bytes=$(wc -c < "$output")"
    done
    modes=(trusted); [ "$variant" = full ] && modes=(full trusted)
    for mode in "${modes[@]}"; do
      for trial in $(seq "$TRIALS"); do
        start=$(now)
        result=$("$BENCH" "$mode" "$output" | tr '\n' ' ')
        echo "$case check-$mode-$variant trial=$trial seconds=$(elapsed "$start" "$(now)") $result"
      done
    done
    if [ "$variant" = filtered ]; then
      # Separate run: classifying contract names imports extra modules, so its wall time is not reported.
      split=$(CONTRACT_MODULES=Requirements,Interpretation,SchemaInputs,SqlInputs "$BENCH" trusted "$output" | tr '\n' ' ')
      echo "$case replay-split $split"
    fi
  done
done
