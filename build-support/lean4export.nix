# lean4export v4.33.0 with the ADR 0003 skip-trusted patch: source for the bundle
# checker's Lake path dependency, and the exporter executable used by `prepare`.
{ pkgs, leanToolchain }:
rec {
  src = pkgs.applyPatches {
    name = "lean4export-v4.33.0-skip-trusted";
    src = pkgs.fetchzip {
      url = "https://github.com/leanprover/lean4export/archive/15f6055e299ad5b89345e533cc2192f4cc00f659.tar.gz";
      hash = "sha256-7yxHyiUlXFVx4xBiSmtoKkh7FSgQrR5SXFgGj06yaaw=";
    };
    patches = [ ./lean4export-skip-trusted.patch ];
  };
  exporter = pkgs.stdenv.mkDerivation {
    pname = "sqlite-verifier-lean4export";
    version = "4.33.0";
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
