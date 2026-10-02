# Invoke with nix-build build-support/default.nix -A TARGET (flakes enabled).
{ system ? builtins.currentSystem
, pkgs ? import ./locked-nixpkgs.nix { inherit system; }
, native ? import ../nix/sqlite.nix { inherit pkgs; }
}:
let
  sources = import ./sources.nix { inherit (pkgs) lib; };
  leanToolchain = import ./lean-toolchain.nix { inherit pkgs; };
  lean4export = import ./lean4export.nix { inherit pkgs leanToolchain; };
  # lakefile.toml requires lean4export as a path dependency at build/lean4export.
  lakeDependencies = ''
    mkdir -p build
    cp -R ${lean4export.src} build/lean4export
    chmod -R u+w build/lean4export
  '';
in rec {
  inherit leanToolchain sources;
  inherit (lean4export) exporter;
  conformanceNative = import ./conformance-native.nix { inherit pkgs; };
  conformanceDocs = import ./conformance-docs.nix {
    inherit pkgs; inherit (conformanceNative) fixture upstream;
  };
  tests = import ./tests.nix {
    inherit pkgs leanToolchain leanRuntime parsers runtime native conformance;
  };
  developmentTests = pkgs.lib.removeAttrs tests [ "model" ];
  runtime = import ./runtime.nix {
    inherit pkgs sources leanToolchain parsers leanRuntime exporter;
  };
  parsers = pkgs.stdenv.mkDerivation {
    pname = "sqlite-verifier-parsers";
    version = "1";
    src = sources.parsers;
    nativeBuildInputs = [ pkgs.python3 ];
    dontConfigure = true;
    buildPhase = pkgs.lib.concatMapStringsSep "\n" (release:
      let
        upstream = "parser/${release.source}";
        directory = "build/${release.directory}";
        hashes = builtins.fromJSON (builtins.readFile (../parser + "/${release.source}/sha256.json"));
      in ''
        (cd ${upstream}; sha256sum --check <<'HASHES'
        ${pkgs.lib.concatStringsSep "\n" (pkgs.lib.mapAttrsToList (name: hash: "${hash}  ${name}") hashes)}
        HASHES
        )
        mkdir -p ${directory}
        $CC ${upstream}/lemon.c -o ${directory}/lemon
        ${directory}/lemon -q -d${directory} -T${upstream}/lempar.c ${upstream}/parse.y
        ${directory}/lemon -E ${upstream}/parse.y > ${directory}/preprocessed.y
        ${directory}/lemon -g ${upstream}/parse.y > ${directory}/grammar.y
        python3 parser/generate.py ${upstream} ${directory}
        ${directory}/lemon -q -T${upstream}/lempar.c ${directory}/syntax.y
        $CC -std=c99 -O1 -Iparser -I${directory} -I${upstream} \
          parser/tokenizer.c ${directory}/syntax.c parser/main.c \
          -lm -lpthread -ldl -o build/${release.executable}
      '') [
        { source = "upstream"; directory = "parser"; executable = "sqlite-parser"; }
        { source = "upstream-3.46.0"; directory = "parser-3.46.0"; executable = "sqlite-parser-3.46.0"; }
      ];
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
      ${lakeDependencies}
      lake build SqliteVerifier migration-proof-checker migration-bundle-checker
    '';
    installPhase = ''
      mkdir -p "$out/.lake/build/bin" "$out/.lake/build/lib"
      cp -R .lake/build/lib/lean "$out/.lake/build/lib/"
      cp .lake/build/bin/migration-proof-checker .lake/build/bin/migration-bundle-checker "$out/.lake/build/bin/"
    '';
  };
  # Test-only model executable; the shipped verifier runtime keeps its existing commands.
  conformanceRuntime = leanRuntime.overrideAttrs (old: {
    pname = "sqlite-verifier-conformance-runtime";
    src = sources.conformanceLean;
    buildPhase = old.buildPhase + "\nlake build VerifierConformance conformance-runner\n";
    installPhase = old.installPhase + ''
      cp .lake/build/bin/conformance-runner "$out/.lake/build/bin/"
    '';
  });
  conformance = pkgs.runCommand "sqlite-verifier-conformance" {} ''
    mkdir -p "$out"
    ln -s ${leanToolchain} "$out/lean"
    ln -s ${conformanceRuntime}/.lake "$out/.lake"
    ln -s ${parsers}/build "$out/build"
  '';
  conformanceCoverage = conformanceRuntime.overrideAttrs (old: {
    pname = "sqlite-verifier-conformance-coverage";
    postPatch = ''${pkgs.python3}/bin/python3 ${../conformance/instrument_model.py} .'';
    buildPhase = ''
      export HOME="$TMPDIR"
      ${lakeDependencies}
      lake build conformance-runner
    '';
    installPhase = ''
      mkdir -p "$out/.lake/build/bin"
      cp .lake/build/bin/conformance-runner "$out/.lake/build/bin/"
      cp coverage-sites.json "$out/"
    '';
  });
}
