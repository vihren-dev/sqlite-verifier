{
  description = "SQLite migration verifier development environment";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-linux" ];
      forSystems = nixpkgs.lib.genAttrs systems;
      packagesFor = system:
        let pkgs = import nixpkgs { inherit system; };
        in { inherit pkgs; } // import ./sqlite.nix { inherit pkgs; };
    in {
      packages = forSystems (system: { inherit (packagesFor system) sqlite sqlite346; });
      checks = forSystems (system:
        let native = packagesFor system;
        in (import ../build-support/default.nix {
          inherit system native;
          inherit (native) pkgs;
        }).tests);
      devShells = forSystems (system:
        let
          tools = packagesFor system;
          testPython = tools.pkgs.python3.withPackages (ps: [ ps.pytest ps.hypothesis ]);
          runtimePackages = with tools.pkgs; [ just coreutils testPython tools.sqlite tools.sqlite346 ]
            ++ lib.optionals stdenv.hostPlatform.isLinux [ patchelf ];
        in {
          default = tools.pkgs.mkShell {
            packages = runtimePackages;
            SQLITE_VERIFIER_SHELL = "default";
            SQLITE_VERIFIER_SYSTEM = system;
            SQLITE_VERIFIER_PYTHON = "${tools.pkgs.python3}/bin/python3";
          };
        });
    };
}
