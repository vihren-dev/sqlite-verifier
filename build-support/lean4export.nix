# lean4export v4.34.0 with the ADR 0003 skip-trusted patch: source for the bundle
# checker's Lake path dependency, and the exporter executable used by `prepare`.
{ pkgs, leanToolchain }:
rec {
  src = pkgs.applyPatches {
    name = "lean4export-v4.34.0-skip-trusted";
    src = pkgs.fetchzip {
      url = "https://github.com/leanprover/lean4export/archive/076e8e57707e813375e8f9da8bf989799ace9680.tar.gz";
      hash = "sha256-sy3UivooYm1t1xdXu+/Fcq0x+U0V/6v19i1c/snnfFo=";
    };
    patches = [ ./lean4export-skip-trusted.patch ];
  };
  exporter = pkgs.stdenv.mkDerivation {
    pname = "sqlite-verifier-lean4export";
    version = "4.34.0";
    inherit src;
    nativeBuildInputs = [ leanToolchain ]
      ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.autoPatchelfHook;
    buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux
      [ pkgs.stdenv.cc.cc.lib pkgs.gmp pkgs.zlib ];
    preFixup = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
      addAutoPatchelfSearchPath ${leanToolchain}/lib
    '';
    dontConfigure = true;
    buildPhase = ''
      export HOME="$TMPDIR"
      lake build lean4export
    '';
    installPhase = ''
      mkdir -p "$out/bin"
      cp .lake/build/bin/lean4export "$out/bin/"
    '';
  };
}
