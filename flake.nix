{
  description = "SQLite migration verifier development environment";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-linux" ];
      forSystems = nixpkgs.lib.genAttrs systems;
      packagesFor = system:
        let pkgs = import nixpkgs { inherit system; };
        in {
          inherit pkgs;
          sqlite = pkgs.stdenv.mkDerivation {
            pname = "sqlite-verifier-native";
            version = "3.51.0";
            src = pkgs.fetchurl {
              url = "https://sqlite.org/2025/sqlite-autoconf-3510000.tar.gz";
              sha256 = "42e26dfdd96aa2e6b1b1be5c88b0887f9959093f650d693cb02eb9c36d146ca5";
            };
            preConfigure = "patchShebangs configure";
            configureFlags = [ "--disable-readline" ];
            meta.license = pkgs.lib.licenses.publicDomain;
          };
        };
    in {
      packages = forSystems (system: { inherit (packagesFor system) sqlite; });
      devShells = forSystems (system:
        let tools = packagesFor system; in {
          default = tools.pkgs.mkShell {
            packages = with tools.pkgs; [ elan just coreutils python3 tools.sqlite ]
              ++ lib.optional stdenv.hostPlatform.isLinux bubblewrap;
          };
        });
    };
}
