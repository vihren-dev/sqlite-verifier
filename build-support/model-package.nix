# Build the standalone model and its separate transport codec without application inputs.
{ pkgs, leanToolchain, source }:
pkgs.stdenvNoCC.mkDerivation {
  pname = "belay-sqlite-model";
  version = "0.1.0";
  src = source;
  nativeBuildInputs = [ leanToolchain ];
  dontConfigure = true;
  buildPhase = ''
    export HOME="$TMPDIR"
    lake build Belay.Sqlite Belay.Sqlite.Codec
  '';
  installPhase = ''
    mkdir -p "$out"
    cp -R Belay .lake lakefile.toml lake-manifest.json lean-toolchain "$out/"
  '';
}
