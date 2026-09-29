# Independent pytest targets: Nix owns isolation, dependency identity and reuse.
{ pkgs, leanToolchain, leanRuntime, parsers, runtime, conformance ? runtime, root ? ../.
, native ? import ../nix/sqlite.nix { inherit pkgs; }
}:
let
  fs = pkgs.lib.fileset;
  common = map (name: root + "/${name}") [
    "pytest.ini" "conftest.py" "tests/__init__.py" "tests/runtime_support.py" "tests/runtime_fixtures.py"
    "tests/runtime_installation.py"
  ];
  python = pkgs.python3.withPackages (ps: [ ps.pytest ]);
  leanRoot = pkgs.runCommand "sqlite-verifier-test-lean" {} ''
    mkdir -p "$out"
    ln -s ${leanToolchain} "$out/lean"
    ln -s ${leanRuntime}/.lake "$out/.lake"
  '';
  suite = name: { file, inputs, runtime, tools ? [], extraFiles ? [] }:
    pkgs.stdenvNoCC.mkDerivation {
      pname = "sqlite-verifier-test-${name}";
      version = "1";
      src = fs.toSource { inherit root; fileset = fs.unions (common ++ [ (root + "/${file}") ] ++ (map (name: root + "/${name}") extraFiles) ++ inputs); };
      nativeBuildInputs = [ python ] ++ tools;
      dontConfigure = true;
      dontBuild = true;
      installPhase = ''
        export HOME="$TMPDIR"
        export PYTEST_DISABLE_PLUGIN_AUTOLOAD=1
        timeout 420 python3 -m pytest ${file} ${pkgs.lib.concatStringsSep " " extraFiles} --runtime-root ${runtime} \
          -p no:cacheprovider --junitxml "$out/junit.xml" -v --durations=10
      '';
    };
in {
  atuin = suite "atuin" {
    file = "tests/atuin_cli_test.py";
    inputs = [];
    inherit runtime;
  };
  cli = suite "cli" {
    file = "tests/cli_test.py";
    inputs = [];
    inherit runtime;
  };
  kernel = suite "kernel" {
    file = "tests/kernel_gate_test.py";
    inputs = [ (fs.fileFilter (file: file.hasExt "lean") (root + /tests/kernel_gate)) ];
    runtime = leanRoot;
  };
  model = suite "model" {
    file = "tests/conformance_model_test.py";
    extraFiles = [ "tests/conformance_trace_test.py" "tests/conformance_pipeline_test.py"
      "tests/conformance_mutation_test.py" ];
    inputs = [
      (fs.fileFilter (file: file.hasExt "py") (root + /migration_check))
      (fs.fileFilter (file: file.hasExt "json") (root + /conformance/cases))
      (root + /SqliteVerifier/SqlExecution.lean)
      (root + /VerifierConformance/Trace.lean)
      (root + /VerifierConformance/Case.lean)
    ] ++ map (name: root + "/conformance/${name}.py") [
      "model_assertions" "model_cases" "model_check"
      "native_fixture" "import_fixture" "schema"
      "case_format" "native_connection" "native_metadata" "native_trace" "pipeline"
    ];
    runtime = conformance;
    tools = [ native.sqlite ];
  };
}
