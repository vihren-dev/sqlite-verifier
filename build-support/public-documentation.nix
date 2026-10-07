# Check authored public documentation without adding tools to the proof runtime.
{ pkgs, sources, leanToolchain, leanRuntime, inventoryTools }:
pkgs.stdenv.mkDerivation {
  pname = "sqlite-verifier-public-documentation";
  version = "1";
  src = sources.lean;
  nativeBuildInputs = [ leanToolchain pkgs.python3 ];
  dontConfigure = true;
  buildPhase = ''
    export LEAN_PATH=${leanRuntime}/.lake/build/lib/lean
    python3 ${inventoryTools}/tools/public_doc_inventory.py --root "$PWD" \
      --lean ${leanToolchain}/bin/lean --output "$PWD/build/public-doc-inventory.json"
  '';
  installPhase = ''
    mkdir -p "$out"
    cp build/public-doc-inventory.json "$out/"
  '';
}
