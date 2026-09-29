# Test-only upstream Tcl execution and native branch instrumentation.
{ pkgs }:
let
  upstream = pkgs.stdenvNoCC.mkDerivation {
    pname = "sqlite-conformance-upstream";
    version = "3.51.0";
    src = pkgs.fetchurl {
      url = "https://www.sqlite.org/2025/sqlite-src-3510000.zip";
      sha256 = "5330719b8b80bf563991ff7a373052943f5357aae76cd1f3367eab845d3a75b7";
    };
    nativeBuildInputs = [ pkgs.unzip ];
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;
    installPhase = ''mkdir -p "$out"; cp -R . "$out/"'';
  };
  fixture = pkgs.stdenv.mkDerivation {
    pname = "sqlite-conformance-testfixture";
    version = "3.51.0";
    src = upstream;
    nativeBuildInputs = [ pkgs.tcl pkgs.pkg-config ];
    buildInputs = [ pkgs.tcl pkgs.zlib ];
    configurePhase = ''
      # The release ZIP omits Fossil's generated tag file. Restore only metadata;
      # mksourceid still verifies every source hash against the original manifest.
      printf 'trunk\nrelease\nmajor-release\nversion-3.51.0\n' > manifest.tags
      ${pkgs.bash}/bin/bash ./configure --prefix="$out" --with-tcl=${pkgs.tcl}/lib --disable-readline
    '';
    buildPhase = "make -j$NIX_BUILD_CORES testfixture sqlite3.c";
    installPhase = ''
      mkdir -p "$out/bin" "$out/source"
      cp testfixture "$out/bin/"
      cp sqlite3.c sqlite3.h "$out/source/"
    '';
  };
in { inherit upstream fixture; }
