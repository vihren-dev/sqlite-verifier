# Independent pytest targets: Nix owns isolation, dependency identity and reuse.
{ pkgs, leanToolchain, leanRuntime, parsers, root ? ../. }:
let
  fs = pkgs.lib.fileset;
  common = map (name: root + "/${name}") [
    "pytest.ini" "conftest.py" "tests/__init__.py" "tests/catalogue.py"
    "tests/case_reports.py" "tests/runtime_support.py" "tests/runtime_fixtures.py"
    "tests/runtime_installation.py"
  ];
  python = pkgs.python3.withPackages (ps: [ ps.pytest ]);
  leanRoot = pkgs.runCommand "sqlite-verifier-test-lean" {} ''
    mkdir -p "$out"
    ln -s ${leanToolchain} "$out/lean"
    ln -s ${leanRuntime}/.lake "$out/.lake"
  '';
  modelRoot = pkgs.runCommand "sqlite-verifier-test-model" {} ''
    mkdir -p "$out"
    ln -s ${leanToolchain} "$out/lean"
    ln -s ${leanRuntime}/.lake "$out/.lake"
    ln -s ${parsers}/build "$out/build"
  '';
  sqlite = (builtins.getFlake (builtins.unsafeDiscardStringContext "path:${../nix}")).packages.${pkgs.stdenv.hostPlatform.system}.sqlite;
  suite = name: { file, inputs, runtime, tools ? [] }:
    pkgs.stdenvNoCC.mkDerivation {
      pname = "sqlite-verifier-test-${name}";
      version = "1";
      src = fs.toSource { inherit root; fileset = fs.unions (common ++ [ (root + "/${file}") ] ++ inputs); };
      nativeBuildInputs = [ python ] ++ tools;
      dontConfigure = true;
      dontBuild = true;
      installPhase = ''
        export HOME="$TMPDIR"
        export PYTEST_DISABLE_PLUGIN_AUTOLOAD=1
        timeout 420 python3 -m pytest ${file} --runtime-root ${runtime} \
          --report-dir "$out" --suite ${name} -v --durations=10
      '';
    };
in {
  kernel = suite "kernel" {
    file = "tests/kernel_gate_test.py";
    inputs = [ (fs.fileFilter (file: file.hasExt "lean") (root + /tests/kernel_gate)) ];
    runtime = leanRoot;
  };
  model = suite "model" {
    file = "tests/conformance_model_test.py";
    inputs = [
      (fs.fileFilter (file: file.hasExt "py") (root + /migration_check))
    ] ++ map (name: root + "/conformance/${name}.py") [
      "model_assertions" "model_cases" "model_check" "model_native"
      "native_fixture" "import_fixture" "schema"
    ];
    runtime = modelRoot;
    tools = [ sqlite ];
  };
}
