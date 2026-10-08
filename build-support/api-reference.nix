# Build the checked public library and its reference without an installed runtime.
{ pkgs, sources, leanToolchain, lean4export, docGen4, inventoryTools, revision }:
let
  sourceRules = pkgs.writeTextDir "tools/source_revision.py"
    (builtins.readFile ../tools/source_revision.py);
  # tests/test_api_reference.py links this Nix guard to the shared Python policy.
  fullCommitHashPattern = "[0-9a-f]{40}";
in
assert builtins.isString revision && builtins.match fullCommitHashPattern revision != null;
pkgs.stdenv.mkDerivation {
  pname = "sqlite-verifier-api-reference";
  version = "${builtins.substring 0 12 revision}";
  src = sources.lean;
  nativeBuildInputs = [ leanToolchain pkgs.python3 ];
  dontConfigure = true;
  buildPhase = ''
    export HOME="$TMPDIR"
    mkdir -p build
    cp -R ${lean4export} build/lean4export
    chmod -R u+w build/lean4export
    lake build SqliteVerifier
    LEAN_PATH="$PWD/.lake/build/lib/lean" python3 ${inventoryTools}/tools/public_doc_inventory.py \
      --root "$PWD" --lean ${leanToolchain}/bin/lean --output "$PWD/build/public-doc-inventory.json"
    PYTHONPATH=${sourceRules} python3 ${../tools/api_reference.py} --root "$PWD" \
      --executable ${docGen4}/bin/doc-gen4 --build "$PWD/build/reference" \
      --revision ${pkgs.lib.escapeShellArg revision}
  '';
  installPhase = ''
    mkdir -p "$out"
    cp -R build/reference/doc/. "$out/"
    cp ${./doc-gen4-sources.json} "$out/doc-gen4-sources.json"
    cp build/public-doc-inventory.json "$out/"
  '';
}
