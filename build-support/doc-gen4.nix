# doc-gen4 and its exact v4.34.1 manifest closure belong only to reference builds.
{ pkgs, leanToolchain }:
let
  pins = builtins.fromJSON (builtins.readFile ./doc-gen4-sources.json);
  sources = builtins.listToAttrs (map (pin: {
    inherit (pin) name;
    value = pkgs.fetchzip {
      url = "https://github.com/${pin.repository}/archive/${pin.revision}.tar.gz";
      inherit (pin) hash;
    };
  }) pins);
  paths = pkgs.writeText "doc-gen4-source-paths.json"
    (builtins.toJSON (builtins.mapAttrs (_: source: toString source) sources));
  sourceRules = pkgs.writeTextDir "tools/source_revision.py"
    (builtins.readFile ../tools/source_revision.py);
in pkgs.stdenv.mkDerivation {
  pname = "sqlite-verifier-doc-gen4";
  version = "4.34.1";
  src = sources.doc-gen4;
  nativeBuildInputs = [ leanToolchain pkgs.python3 pkgs.makeWrapper ]
    ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.autoPatchelfHook;
  buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux
    [ pkgs.stdenv.cc.cc.lib pkgs.gmp pkgs.zlib ];
  preFixup = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
    addAutoPatchelfSearchPath ${leanToolchain}/lib
  '';
  postPatch = ''
    PYTHONPATH=${sourceRules} python3 ${../tools/docgen_dependencies.py} . ${./doc-gen4-sources.json} ${paths}
  '';
  dontConfigure = true;
  buildPhase = ''
    export HOME="$TMPDIR"
    lake build doc-gen4
  '';
  installPhase = ''
    mkdir -p "$out/bin"
    cp .lake/build/bin/doc-gen4 "$out/bin/"
    wrapProgram "$out/bin/doc-gen4" --set LEAN_SYSROOT ${leanToolchain}
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    "$out/bin/doc-gen4" --help
  '';
}
