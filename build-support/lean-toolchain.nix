# Upstream release asset SHA-256 digests, verified against downloaded 4.33.0 archives.
{ pkgs }:
let
  version = "4.33.0";
  archives = {
    aarch64-darwin = {
      platform = "darwin_aarch64";
      hash = "sha256:db5274b669be270af048b5e4f1e0ce571df6750e411956b3e1e6fcc2012410c2";
    };
    x86_64-linux = {
      platform = "linux";
      hash = "sha256:4b3fb03c29a1e0a253fb1d11f9bae3725f19a0dc6fc09b3ea16d2c9df3349e2c";
    };
  };
  archive = archives.${pkgs.stdenv.hostPlatform.system}
    or (throw "Lean toolchain supports only aarch64-darwin and x86_64-linux");
in
assert builtins.readFile ../lean-toolchain == "leanprover/lean4:v${version}\n";
pkgs.stdenv.mkDerivation {
  pname = "sqlite-verifier-lean";
  inherit version;
  src = pkgs.fetchurl {
    url = "https://github.com/leanprover/lean4/releases/download/v${version}/lean-${version}-${archive.platform}.tar.zst";
    inherit (archive) hash;
  };
  nativeBuildInputs = [ pkgs.zstd ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.autoPatchelfHook ];
  buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.stdenv.cc.cc.lib pkgs.gmp pkgs.zlib ];
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R . "$out/"
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    "$out/bin/lean" --version | grep -F 'Lean (version ${version},'
    "$out/bin/lake" --version
  '';
}
