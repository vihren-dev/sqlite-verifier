# Invoke with nix-build build-support/default.nix -A TARGET (flakes enabled).
{ system ? builtins.currentSystem }:
let
  pkgs = import ./locked-nixpkgs.nix { inherit system; };
  sources = import ./sources.nix { inherit (pkgs) lib; };
  leanToolchain = import ./lean-toolchain.nix { inherit pkgs; };
in rec {
  inherit leanToolchain sources;
  unitChecks = pkgs.stdenvNoCC.mkDerivation {
    pname = "sqlite-verifier-unit-checks";
    version = "1";
    src = sources.unit;
    nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.pytest ])) ];
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      export HOME="$TMPDIR"
      timeout 120 python3 build-support/run_unit_checks.py "$out"
    '';
  };
  runtime = import ./runtime.nix {
    inherit pkgs sources leanToolchain parsers leanRuntime;
  };
  parsers = pkgs.stdenv.mkDerivation {
    pname = "sqlite-verifier-parsers";
    version = "1";
    src = sources.parsers;
    nativeBuildInputs = [ pkgs.python3 ];
    dontConfigure = true;
    buildPhase = "python3 parser/build.py";
    installPhase = ''
      mkdir -p "$out"
      cp -R build "$out/"
    '';
  };
  leanRuntime = pkgs.stdenv.mkDerivation {
    pname = "sqlite-verifier-lean-runtime";
    version = "1";
    src = sources.lean;
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
      lake build SqliteVerifier migration-proof-checker
    '';
    installPhase = ''
      mkdir -p "$out/.lake/build/bin" "$out/.lake/build/lib"
      cp -R .lake/build/lib/lean "$out/.lake/build/lib/"
      cp .lake/build/bin/migration-proof-checker "$out/.lake/build/bin/"
    '';
  };
}
