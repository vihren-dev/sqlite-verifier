# Build the checked public library and its reference without an installed runtime.
# Source links contain a placeholder, so this build depends only on the Lean sources and
# the pinned tools; api-reference-links.nix adds the checked commit in a cheap step.
{ pkgs, sources, leanToolchain, lean4export, docGen4, inventoryTools }:
let
  sourceRules = pkgs.writeTextDir "tools/source_revision.py"
    (builtins.readFile ../tools/source_revision.py);
in
pkgs.stdenv.mkDerivation {
  pname = "sqlite-verifier-api-reference-base";
  version = "1";
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
      --executable ${docGen4}/bin/doc-gen4 --build "$PWD/build/reference"
  '';
  installPhase = ''
    mkdir -p "$out"
    cp -R build/reference/doc/. "$out/"
    cp ${./doc-gen4-sources.json} "$out/doc-gen4-sources.json"
    cp build/public-doc-inventory.json "$out/"
  '';
}
