# Independent pytest targets: Nix owns isolation, dependency identity and reuse.
{ pkgs, leanToolchain, leanRuntime, parsers, runtime, conformance ? runtime, root ? ../.
, native ? import ../nix/sqlite.nix { inherit pkgs; }
, conformanceNative ? import ./conformance-native.nix { inherit pkgs; }
}:
let
  fs = pkgs.lib.fileset;
  common = map (name: root + "/${name}") [
    "pytest.ini" "conftest.py" "tests/__init__.py" "tests/runtime_support.py" "tests/runtime_fixtures.py"
    "tests/runtime_installation.py"
  ];
  python = name: pkgs.python3.withPackages (ps: [ ps.pytest ps.pytest-timeout ]
    ++ pkgs.lib.optional (name == "model") ps.hypothesis);
  # Each test has its own limit, so a hang fails with the name of the test. Nix runs suites
  # in parallel, so the suite limit only guards against a hang outside a test and must not
  # depend on how many suites share the CPU (reports/20261006-hosted-model-timeout/README.md).
  testTimeoutSeconds = 300;
  suiteTimeoutSeconds = 1200;
  # The conformance suites use only the SQL frontend, not the verification application.
  # tests/test_conformance_frontend.py checks this list against the actual imports.
  frontend = map (name: root + "/migration_check/${name}.py")
    (builtins.fromJSON (builtins.readFile (root + /tests/conformance_frontend.json)));
  leanRoot = pkgs.runCommand "sqlite-verifier-test-lean" {} ''
    mkdir -p "$out"
    ln -s ${leanToolchain} "$out/lean"
    ln -s ${leanRuntime}/.lake "$out/.lake"
  '';
  suite = name: { inputs, runtime, tools ? [], environment ? {} }:
    let
      files = (builtins.fromJSON (builtins.readFile (root + /tests/nix_suites.json))).${name};
      file = builtins.head files;
      extraFiles = builtins.tail files;
    in pkgs.stdenvNoCC.mkDerivation ({
      pname = "sqlite-verifier-test-${name}";
      version = "1";
      src = fs.toSource { inherit root; fileset = fs.unions (common ++ [ (root + "/${file}") ] ++ (map (name: root + "/${name}") extraFiles) ++ inputs); };
      nativeBuildInputs = [ (python name) ] ++ tools;
      dontConfigure = true;
      dontBuild = true;
      installPhase = ''
        export HOME="$TMPDIR"
        export PYTEST_DISABLE_PLUGIN_AUTOLOAD=1
        timeout ${toString suiteTimeoutSeconds} python3 -m pytest ${file} ${pkgs.lib.concatStringsSep " " extraFiles} --runtime-root ${runtime} \
          -p no:cacheprovider -p pytest_timeout --timeout=${toString testTimeoutSeconds} \
          --junitxml "$out/junit.xml" -v --durations=10
      '';
    } // environment);
  # Inputs shared by the three suites that the old single model suite contained.
  modelInputs = frontend ++ [
    (root + /tests/conformance_freeze_capture.py)
    (fs.fileFilter (file: file.hasExt "json") (root + /conformance/cases))
    (root + /SqliteVerifier/SqlExecution.lean)
    (root + /SqliteVerifier/Execution.lean) (root + /SqliteVerifier/LiteralData.lean)
    (root + /VerifierConformance/Trace.lean)
    (root + /VerifierConformance/Outputs.lean)
    (root + /VerifierConformance/Case.lean)
    (root + /VerifierConformance/Laws.lean)
    (root + /conformance/requirements-3.51.0.json)
    (root + /conformance/regressions)
    (root + /conformance/synthetic-workload)
    (root + /conformance/upstream_proxy.tcl)
    (root + /conformance/upstream_external.tcl)
    (root + /conformance/upstream_bindings.tcl)
    (root + /nix/sqlite.nix)
    (root + /nix/flake.lock)
    (root + /build-support/conformance-native.nix)
  ] ++ map (name: root + "/conformance/${name}.py") [
    "model_assertions" "model_cases" "model_check" "replay_tiers" "native_workers"
    "execution_profile" "native_acquisition"
    "native_storage"
    "refresh_corpus" "requirement_cases" "requirement_coverage"
    "authored_cases" "authored_cases_queries" "authored_boundaries" "authored_review" "authored_report"
    "authored_transactions" "transaction_evidence"
    "upstream_selection" "upstream_catalog" "upstream_sampling" "upstream_profiles" "upstream_functions" "upstream_result_values"
    "corpus_shards" "corpus_workers" "corpus_evidence" "corpus_acquisition" "freeze_corpus" "freeze_validation" "freeze_profiles" "workload" "workload_inputs"
    "upstream_assertions"
    "native_bindings" "native_call_recording" "native_binding_types" "native_binding_validation"
    "native_observation"
    "upstream_bindings" "upstream_binding_policy" "upstream_display" "upstream_evidence"
    "upstream_helpers"
    "native_fixture" "import_fixture" "schema"
    "case_format" "native_connection" "native_library" "native_clock" "native_probe" "native_ordering" "query_window" "native_metadata" "native_record" "native_statements" "native_replay" "upstream_pilot" "upstream_fidelity" "corpus" "generated_program" "mutation_check" "state_machine" "regressions" "progress" "measure_coverage" "native_trace" "pipeline"
  ];
  # Frozen corpora and retained reports: large, rarely changed, read only by the frozen suite.
  frozenData = [
    (root + /conformance/corpus-v1)
    (root + /reports/20260929-adr4-corpus-v2-progress.json)
    (root + /reports/20261001-adr5-c4-fidelity.json)
    (root + /reports/20261001-adr5-c4-causes.json.gz)
    (root + /reports/20261001-adr5-c4-traces.json.gz)
    (root + /reports/20261001-adr5-c4-mechanical.json.gz)
    (root + /reports/20261001-adr5-c4-bindings.json.gz)
    (root + /reports/20261001-adr5-c5-authored.json)
    (root + /reports/20261001-adr5-c5-authored-records.jsonl.gz)
    (root + /reports/20261006-grouped-immediate-transactions)
    (root + /conformance/corpus-v5)
    (root + /conformance/corpus-v4)
    (root + /conformance/corpus-v3)
    (root + /conformance/corpus-v2)
  ];
  modelTools = [ native.sqlite native.sqlite346 native.sqlite3534 ];
in {
  sample = suite "sample" {
    inputs = frontend ++ [
      (root + /tests/native_worker_fixtures.py)
      (root + /conformance/corpus-v5)
      (root + /conformance/synthetic-workload)
    ] ++ map (name: root + "/conformance/${name}.py") [
      "replay_tiers" "native_workers" "corpus" "corpus_shards" "corpus_workers" "corpus_evidence" "corpus_acquisition" "case_format"
      "workload" "workload_inputs" "execution_profile" "native_replay" "model_check"
      "native_record" "native_observation" "native_acquisition" "native_connection" "native_library" "native_clock" "native_storage"
      "native_probe" "native_ordering" "query_window" "native_metadata" "native_statements"
      "native_bindings" "native_call_recording" "upstream_bindings" "upstream_binding_policy"
      "native_binding_types" "native_binding_validation"
      "upstream_helpers" "model_assertions" "native_trace" "freeze_validation"
      "upstream_catalog" "upstream_sampling" "upstream_profiles" "freeze_profiles"
      "upstream_result_values" "upstream_fidelity" "upstream_display"
    ];
    runtime = conformance;
    tools = [ native.sqlite ];
  };
  upstream = suite "upstream" {
    inputs = frontend ++ [
      (root + /tests/conformance_freeze_capture.py)
      (fs.fileFilter (file: file.hasExt "py" || file.hasExt "tcl") (root + /conformance))
      (root + /conformance/requirements-3.51.0.json)
      (root + /conformance/corpus-v1)
      (root + /conformance/corpus-v2)
      (root + /conformance/corpus-v3)
      (root + /conformance/corpus-v4)
      (root + /tools/__init__.py)
      (root + /tools/check_resources.py)
      (root + /nix/flake.nix)
      (root + /nix/flake.lock)
      (root + /nix/sqlite.nix)
      (root + /build-support/conformance-native.nix)
      (root + /tests/upstream_profile_calls.test)
      (root + /tests/upstream_helper_calls.test)
      (root + /tests/upstream_context_calls.test)
      (root + /tests/upstream_attachment_calls.test)
      (root + /tests/upstream_nondeterminism_calls.test)
      (root + /tests/upstream_storage_calls.test)
      (root + /tests/upstream_fidelity_calls.test)
      (root + /tests/upstream_sampling_calls.test)
      (root + /tests/upstream_external_calls.test)
      (root + /tests/upstream_source_calls.test)
      (root + /tests/upstream_registered_calls.test)
      (root + /tests/upstream_value_calls.test)
      (root + /tests/upstream_binding_calls.test)
    ];
    runtime = conformance;
    tools = [ native.sqlite conformanceNative.fixture ];
    environment.CONFORMANCE_UPSTREAM = conformanceNative.upstream;
  };
  atuin = suite "atuin" {
    inputs = [];
    inherit runtime;
  };
  bundle = suite "bundle" {
    inputs = [
      (fs.fileFilter (file: file.hasExt "py") (root + /migration_check))
      (fs.fileFilter (file: file.hasExt "json") (root + /conformance/cases))
      (root + /tests/sql_fixtures.py)
    ];
    inherit runtime;
  };
  cli = suite "cli" {
    inputs = [];
    inherit runtime;
  };
  kernel = suite "kernel" {
    inputs = [ (fs.fileFilter (file: file.hasExt "lean") (root + /tests/kernel_gate)) ];
    runtime = leanRoot;
  };
  model = suite "model" {
    inputs = modelInputs;
    runtime = conformance;
    tools = modelTools;
  };
  frozen = suite "frozen" {
    inputs = modelInputs ++ frozenData;
    runtime = conformance;
    tools = modelTools;
  };
  harness = suite "harness" {
    inputs = modelInputs;
    runtime = conformance;
    tools = modelTools;
  };
}
