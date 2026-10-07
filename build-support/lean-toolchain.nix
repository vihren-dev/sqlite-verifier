# Official release asset SHA-256 digests; Nix verifies the downloaded archives.
{ pkgs }:
let
  version = "4.34.1";
  archives = {
    aarch64-darwin = {
      platform = "darwin_aarch64";
      hash = "sha256:65f22a4f047738ec742667b3247e836a86ebf06eabc12655c3dee00637e37866";
    };
    x86_64-linux = {
      platform = "linux";
      hash = "sha256:47bf4bbd78f70c2e9670598ab7124d92b6efb7330ff33e5fbb4030f6fd72e4e4";
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
