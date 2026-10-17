# Invoke with nix-build build-support/default.nix -A TARGET (flakes enabled).
{ root ? ../.
, system ? builtins.currentSystem
, pkgs ? import ./locked-nixpkgs.nix { inherit system; }
, native ? import ../nix/sqlite.nix { inherit pkgs; }
, referenceRevision ? null
}:
let
  sources = import ./sources.nix { inherit (pkgs) lib; inherit root; };
  leanToolchain = import ./lean-toolchain.nix { inherit pkgs; };
  lean4export = import ./lean4export.nix { inherit pkgs; };
  inventoryTools = pkgs.lib.fileset.toSource {
    root = ../.;
    fileset = pkgs.lib.fileset.unions [ ../tools/public_doc_coverage.py ../tools/public_doc_inventory.py ];
  };
  # One Nix derivation for each Lean package under packages/ (ADR 0010 section 7).
  leanPackage = arguments: import ./lean-package.nix ({ inherit pkgs leanToolchain; } // arguments);
in rec {
  inherit leanToolchain sources;
  # The standalone model and its separate transport codec, without application inputs.
  modelPackage = leanPackage {
    pname = "belay-sqlite-model";
    directory = "packages/belay-sqlite";
    source = sources.model;
    targets = [ "Belay.Sqlite" "Belay.Sqlite.Codec" ];
  };
  sqlite3534 = native.sqlite3534;
  docGen4 = import ./doc-gen4.nix { inherit pkgs leanToolchain; };
  apiReferenceCore = import ./api-reference-core.nix { inherit pkgs leanToolchain docGen4; };
  apiReferenceBase = import ./api-reference.nix {
    inherit pkgs leanToolchain docGen4 modelPackage verifierLibrary;
    core = apiReferenceCore;
  };
  apiReference = import ./api-reference-links.nix {
    inherit pkgs;
    base = apiReferenceBase;
    revision = referenceRevision;
  };
  publicDocumentation = import ./public-documentation.nix {
    inherit pkgs leanToolchain verifierLibrary inventoryTools docTools modelPackage;
  };
  conformanceNative = import ./conformance-native.nix { inherit pkgs; };
  conformanceDocs = import ./conformance-docs.nix {
    inherit pkgs; inherit (conformanceNative) fixture upstream;
  };
  allTests = import ./tests.nix {
    inherit pkgs leanToolchain leanRuntime runtime seedRuntime native conformance modelPackage root;
    parserLibrary = parserLibrary.testRoot;
    inherit leanPackages;
  };
  # Suites that only main pushes and scheduled runs build (`just test-scheduled`), so that the CI
  # time of pull requests does not grow; tests/nix_scheduled_suites.json lists them.
  scheduledSuites = builtins.fromJSON (builtins.readFile ../tests/nix_scheduled_suites.json);
  tests = pkgs.lib.removeAttrs allTests scheduledSuites;
  scheduledTests = pkgs.lib.getAttrs scheduledSuites allTests;
  # `just test` skips the slow model comparisons, the frozen evidence and the locked-corpus
  # validation; `just test-full` runs them.
  developmentTests = pkgs.lib.removeAttrs tests [ "model" "frozen" "corpora" ];
  runtime = import ./runtime.nix {
    inherit pkgs sources leanToolchain verifierLibrary leanRuntime modelPackage;
    parserLibrary = parserLibrary.library;
  };
  # The runtime without examples/, for the case seeds: a change to one example rebuilds only its seed.
  seedRuntime = import ./runtime.nix {
    inherit pkgs sources leanToolchain verifierLibrary leanRuntime modelPackage;
    parserLibrary = parserLibrary.library;
    src = sources.runtimeWithoutExamples;
  };
  # The in-process SQLite parser library of the verifier and the harness; tests.parserLibrary checks it.
  parserLibrary = import ./parser-library.nix { inherit pkgs root; };
  verifierLibrary = leanPackage {
    pname = "sqlite-verifier-library";
    directory = "packages/sqlite-verifier";
    source = sources.verifierLibrary;
    targets = [ "SqliteVerifier" "EngineeringExamples" "GatePaths" "GateCore" "GateInputs" ];
    requires."packages/belay-sqlite" = modelPackage;
  };
  # The exporter library that the gate's executables import; built once, here, not in each gate build.
  lean4exportPackage = leanPackage {
    pname = "lean4export-library";
    directory = "build/lean4export";
    source = lean4export;
    # The `Export` library's root does not import `Export.Parse`, which the bundle checker uses.
    targets = [ "Export" "+Export.Parse" ];
  };
  verifierGate = leanPackage {
    pname = "sqlite-verifier-gate";
    directory = "packages/verifier-gate";
    source = sources.verifierGate;
    targets = [ "migration-proof-checker" "migration-bundle-checker" "migration-proof-exporter" "migration-resolver" ];
    requires = { "packages/belay-sqlite" = modelPackage; "packages/sqlite-verifier" = verifierLibrary;
                 "build/lean4export" = lean4exportPackage; };
    executables = true;
  };
  verifierConformance = leanPackage {
    pname = "sqlite-verifier-conformance-package";
    directory = "packages/verifier-conformance";
    source = sources.verifierConformance;
    targets = [ "VerifierConformance" "conformance-runner" ];
    requires."packages/belay-sqlite" = modelPackage;
    executables = true;
  };
  # The built Lean packages by their folder in the repository layout; tests.packages replays them.
  leanPackages = {
    "packages/belay-sqlite" = modelPackage; "packages/sqlite-verifier" = verifierLibrary;
    "packages/verifier-gate" = verifierGate; "packages/verifier-conformance" = verifierConformance;
    "packages/public-doc-tools" = docTools; "build/lean4export" = lean4exportPackage;
  };
  # The documentation inventory's Lean part; publicDocumentation and tests.documentation use it.
  docTools = leanPackage {
    pname = "sqlite-verifier-doc-tools";
    directory = "packages/public-doc-tools";
    source = sources.docTools;
    targets = [ "PublicDocSyntax" "PublicDocInventory" ];
  };
  # The library outputs and the gate's binaries in the layout that the installed runtime ships.
  leanRuntime = pkgs.runCommand "sqlite-verifier-lean-runtime" { } ''
    mkdir -p "$out/.lake/build/bin" "$out/.lake/build/lib"
    cp -R ${verifierLibrary}/.lake/build/lib/lean "$out/.lake/build/lib/"
    # Lake replays the library only when the outputs each trace lists exist, including `ir` (ADR 0010).
    cp -R ${verifierLibrary}/.lake/build/ir "$out/.lake/build/"
    cp ${verifierGate}/.lake/build/bin/migration-proof-checker ${verifierGate}/.lake/build/bin/migration-bundle-checker \
      ${verifierGate}/.lake/build/bin/migration-proof-exporter ${verifierGate}/.lake/build/bin/migration-resolver \
      "$out/.lake/build/bin/"
  '';
  # Test-only model executable and library next to the runtime's; the shipped runtime keeps its commands.
  conformanceRuntime = pkgs.runCommand "sqlite-verifier-conformance-runtime" { } ''
    mkdir -p "$out/.lake/build"
    cp -R ${leanRuntime}/.lake/build/. "$out/.lake/build/"
    chmod -R u+w "$out/.lake/build"
    cp -R ${verifierConformance}/.lake/build/lib/lean/. "$out/.lake/build/lib/lean/"
    cp ${verifierConformance}/.lake/build/bin/conformance-runner "$out/.lake/build/bin/"
  '';
  conformance = pkgs.runCommand "sqlite-verifier-conformance" {} ''
    mkdir -p "$out"
    ln -s ${leanToolchain} "$out/lean"
    ln -s ${conformanceRuntime}/.lake "$out/.lake"
    mkdir -p "$out/packages"
    ln -s ${modelPackage} "$out/packages/belay-sqlite"
    ln -s ${parserLibrary.library}/lib "$out/lib"
  '';
  # The runner built against an instrumented copy of the model's sources, which compiles here.
  conformanceCoverage = (leanPackage {
    pname = "sqlite-verifier-conformance-coverage";
    directory = "packages/verifier-conformance";
    source = sources.verifierConformance;
    targets = [ "conformance-runner" ];
    requires."packages/belay-sqlite" = sources.model;
    executables = true;
  }).overrideAttrs (old: {
    postPatch = ''
      ${pkgs.python3}/bin/python3 ${../conformance/instrument_model.py} ../..
    '';
    installPhase = ''
      mkdir -p "$out/.lake/build/bin"
      cp .lake/build/bin/conformance-runner "$out/.lake/build/bin/"
      cp ../../coverage-sites.json "$out/"
    '';
  });
}
