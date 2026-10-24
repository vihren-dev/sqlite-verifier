# ADR 0011: the locked judge and the verdict. `.github/CODEOWNERS` protects this file and
# integrity/judge.lock.json; the verdict job runs `nix-build integrity/judge.nix -A verdict`.
#
# Each lock entry is the content-derived store path of one part of the judge: the judge code
# with its claims, each claimed corpus, and the native SQLite oracle with its pinned inputs,
# which include the nixpkgs pin that this file uses. A content-derived path is computed from
# the files every time; a fixed-output path with a declared hash would reuse an existing
# store path without reading the files.
#
# This file imports nothing that the lock does not cover, except the subject's build: the
# subject is what the judge grades, and it runs where the recorded observations are absent.
{ system ? builtins.currentSystem }:
let
  flake = builtins.fromJSON (builtins.readFile ../nix/flake.lock);
  nixpkgs = flake.nodes.${flake.nodes.${flake.root}.inputs.nixpkgs}.locked;
  pkgs = import (builtins.fetchTree {
    inherit (nixpkgs) type owner repo rev narHash;
  }) { inherit system; };
  fs = pkgs.lib.fileset;
  root = ../.;
  lock = builtins.fromJSON (builtins.readFile ./judge.lock.json);
  claims = builtins.fromJSON (builtins.readFile ../judge/claims.json);
  part = files: "${fs.toSource { inherit root; fileset = fs.unions files; }}";
  # The judge's sources: its code and claims, without files that running it leaves behind.
  judgeFiles = fs.fileFilter (file: file.hasExt "py" || file.hasExt "json") ../judge;
  parts = {
    judge = part [ judgeFiles ];
    oracle = part [ ../nix/sqlite.nix ../nix/flake.lock ];
  } // pkgs.lib.mapAttrs' (corpus: entry: {
    name = "corpus ${corpus}";
    value = part [ (root + "/${entry.path}") ];
  }) claims.corpora;
  changed = builtins.filter (name: (lock.${name} or null) != parts.${name}) (builtins.attrNames parts);
  extra = builtins.filter (name: !(parts ? ${name})) (builtins.attrNames lock);
  checked = value:
    if changed == [] && extra == [] then value
    else throw ("the judge changed: ${pkgs.lib.concatStringsSep ", " (changed ++ extra)}"
      + " differs from integrity/judge.lock.json. A change to the judge, the claims, a corpus or the"
      + " oracle needs the owner's approval: update integrity/judge.lock.json in its own pull request"
      + " (just judge-lock prints the new values).");
  judgeSources = fs.toSource { inherit root; fileset = fs.unions
    ([ judgeFiles ] ++ map (entry: root + "/${entry.path}") (builtins.attrValues claims.corpora)); };
  # The judge runs with only the standard library and its own package on the import path.
  judge = mode: arguments: ''
    cd ${judgeSources}
    ${pkgs.python3}/bin/python3 -I -c 'import runpy, sys; sys.path.insert(0, "."); runpy.run_module("judge", run_name="__main__", alter_sys=True)' \
      ${mode} --root . --claims judge/claims.json ${arguments}
  '';
  # The subject: the frontend, the model and its predict command, built from the same commit.
  subject = import ../build-support/default.nix { inherit system; };
  # Python bytecode is generated during local runs and is not a source input.
  subjectSources = fs.toSource { inherit root; fileset = fs.unions
    (map (fs.fileFilter (file: file.hasExt "py")) [ ../belay ../conformance ]); };
  inputs = checked (pkgs.runCommand "sqlite-verifier-judge-inputs" {} (judge "inputs" ''--out "$out"''));
  # The subject sees only its inputs: the corpora are not inputs of this build.
  predictions = pkgs.runCommand "sqlite-verifier-predictions" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    mkdir -p "$out"
    cd "$TMPDIR"
    for given in ${inputs}/*.jsonl; do
      PYTHONPATH=${subjectSources} python3 -m conformance.predict --runtime ${subject.conformance} \
        < "$given" > "$out/$(basename "$given")"
    done
  '';
in {
  # The current values, for `just judge-lock`; reading them does not check the lock.
  current = parts;
  # The lock check alone, without building the subject.
  locked = checked true;
  inherit inputs predictions;
  # The verdict: the locked judge's check of the subject's predictions.
  verdict = checked (pkgs.runCommand "sqlite-verifier-verdict" {} ''
    mkdir -p "$out"
    ${judge "verdict" ''--predictions ${predictions} --report "$out/report.json" > "$out/counts.json"''}
    cat "$out/counts.json"
  '');
}
