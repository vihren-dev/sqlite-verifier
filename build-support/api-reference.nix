# Add our public modules to a copy of the cached core documentation and write the pages.
# Source links contain a placeholder, so this build depends only on the Lean sources, the core
# build and the pinned tools; api-reference-links.nix adds the checked commit in a cheap step.
{ pkgs, sources, leanToolchain, lean4export, docGen4, core, modelPackage }:
let
  sourceRules = pkgs.writeTextDir "tools/source_revision.py"
    (builtins.readFile ../tools/source_revision.py);
in
pkgs.stdenv.mkDerivation {
  pname = "sqlite-verifier-api-reference-base";
  version = "2";
  src = sources.lean;
  nativeBuildInputs = [ leanToolchain pkgs.python3 ];
  dontConfigure = true;
  buildPhase = ''
    export HOME="$TMPDIR"
    mkdir -p build packages
    cp -R ${modelPackage} packages/belay-sqlite
    chmod -R u+w packages/belay-sqlite
    cp -R ${lean4export} build/lean4export
    chmod -R u+w build/lean4export
    lake build SqliteVerifier EngineeringExamples
    cp -R ${core} build/reference
    chmod -R u+w build/reference
    PYTHONPATH=${sourceRules} python3 ${../tools/api_reference.py} --root "$PWD" \
      --executable ${docGen4}/bin/doc-gen4 --build "$PWD/build/reference"
  '';
  installPhase = ''
    mkdir -p "$out"
    cp -R build/reference/doc/. "$out/"
    cp ${./doc-gen4-sources.json} "$out/doc-gen4-sources.json"
  '';
}
