# Rebuild requirement-marked HTML with SQLite's own versioned documentation tools.
{ pkgs, fixture, upstream }:
pkgs.stdenv.mkDerivation {
  pname = "sqlite-conformance-requirements";
  version = "3.51.0";
  src = ../conformance/upstream-docsrc-3.51.0.tar.gz;
  nativeBuildInputs = [ pkgs.tcl pkgs.gnumake pkgs.fossil ];
  buildInputs = [ pkgs.tcl pkgs.zlib ];
  dontConfigure = true;
  buildPhase = ''
    make CC="$CC -I${fixture}/source" SRC=${upstream} BLD=${fixture}/source \
      TCLINC=-I${pkgs.tcl}/include TCLFLAGS="-L${pkgs.tcl}/lib -ltcl8.6 -lz -lm -lpthread" \
      TH3= SLT= base evidence
    ./tclsh.docsrc matrix.tcl > matrix.log
  '';
  installPhase = ''
    mkdir -p "$out"
    cp docinfo.db matrix.log manifest.uuid manifest.tags "$out/"
    cp -R doc "$out/"
  '';
}
