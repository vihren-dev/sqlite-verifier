{
  description = "SQLite migration verifier development environment";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-linux" ];
      forSystems = nixpkgs.lib.genAttrs systems;
      packagesFor = system:
        let pkgs = import nixpkgs { inherit system; };
            sqliteRelease = version: year: number: sha256: pkgs.stdenv.mkDerivation {
            pname = "sqlite-verifier-native";
            inherit version;
            src = pkgs.fetchurl {
              url = "https://sqlite.org/${year}/sqlite-autoconf-${number}.tar.gz";
              inherit sha256;
            };
            preConfigure = "patchShebangs configure";
            configureFlags = [ "--disable-readline" ];
            meta.license = pkgs.lib.licenses.publicDomain;
          };
        in {
          inherit pkgs;
          sqlite = sqliteRelease "3.51.0" "2025" "3510000"
            "42e26dfdd96aa2e6b1b1be5c88b0887f9959093f650d693cb02eb9c36d146ca5";
          sqlite346 = (sqliteRelease "3.46.0" "2024" "3460000"
            "6f8e6a7b335273748816f9b3b62bbdc372a889de8782d7f048c653a447417a7d").overrideAttrs {
              postInstall = "mv $out/bin/sqlite3 $out/bin/sqlite3-3.46.0";
            };
        };
    in {
      packages = forSystems (system: { inherit (packagesFor system) sqlite sqlite346; });
      devShells = forSystems (system:
        let
          tools = packagesFor system;
          runtimePackages = with tools.pkgs; [ elan just coreutils python3 tools.sqlite tools.sqlite346 ]
            ++ lib.optional stdenv.hostPlatform.isLinux bubblewrap;
        in {
          default = tools.pkgs.mkShell {
            packages = runtimePackages;
            SQLITE_VERIFIER_SHELL = "default";
            SQLITE_VERIFIER_SYSTEM = system;
          };
          # Capture upstream runner behavior with the Rust tools fixed by flake.lock.
          capture = tools.pkgs.mkShell {
            packages = runtimePackages ++ (with tools.pkgs; [ cargo rustc pkg-config ]);
            SQLITE_VERIFIER_SHELL = "capture";
            SQLITE_VERIFIER_SYSTEM = system;
          };
        });
    };
}
