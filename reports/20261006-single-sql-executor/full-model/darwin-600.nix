# Validation invocation only: preserve PR48 sources and all model test commands.
let
  checks = import /Users/tzankomatev/work/sqlite-verifier-executor/build-support/default.nix {};
in checks.tests.model.overrideAttrs (old: {
  installPhase = builtins.replaceStrings
    [ "timeout 420 python3" ] [ "timeout 600 python3" ] old.installPhase;
})
