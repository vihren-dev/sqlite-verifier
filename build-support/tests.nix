# Independent pytest targets: Nix owns isolation, dependency identity and reuse.
{ pkgs, leanToolchain, leanRuntime, runtime, seedRuntime, modelPackage, parserLibrary, conformance ? runtime, root ? ../.
# Lean package outputs by their folder in the repository layout (default.nix); the `packages` suite replays them.
, leanPackages
, native ? import ../nix/sqlite.nix { inherit pkgs; }
, conformanceNative ? import ./conformance-native.nix { inherit pkgs; }
}:
let
  fs = pkgs.lib.fileset;
  common = map (name: root + "/${name}") [
    "pytest.ini" "conftest.py" "tests/__init__.py" "tests/runtime_support.py" "tests/runtime_fixtures.py"
    "tests/runtime_installation.py"
  ];
  # The belay.toml reader, for targets whose tests take the checked-in cases from belay.toml (ADR 0010).
  # Only these targets list it, so a change to the reader does not rerun the conformance targets.
  caseReader = map (name: root + "/${name}") [ "migration_check/__init__.py" "migration_check/project_config.py" ];
  python = name: pkgs.python3.withPackages (ps: [ ps.pytest ps.pytest-timeout ]
    ++ pkgs.lib.optional (name == "model") ps.hypothesis);
  # Each test has its own limit, so a hang fails with the name of the test. Nix runs suites
  # in parallel, so the suite limit only guards against a hang outside a test and must not
  # depend on how many suites share the CPU (reports/20261006-hosted-model-timeout/README.md).
  testTimeoutSeconds = 300;
  suiteTimeoutSeconds = 1200;
  # The conformance suites use only the SQL frontend, not the verification application.
  # tests/test_conformance_frontend.py checks this list against the actual imports.
  frontend = map (name: root + "/${builtins.replaceStrings [ "." ] [ "/" ] name}.py")
    (builtins.fromJSON (builtins.readFile (root + /tests/conformance_frontend.json)));
  leanRoot = pkgs.runCommand "sqlite-verifier-test-lean" {} ''
    mkdir -p "$out"
    ln -s ${leanToolchain} "$out/lean"
    ln -s ${leanRuntime}/.lake "$out/.lake"
    mkdir -p "$out/packages"
    ln -s ${modelPackage} "$out/packages/belay-sqlite"
  '';
  # The package outputs in the repository layout. Each package folder is a real folder, so the relative
  # paths of its requirements resolve here; its entries link to the store, because Lake must not write.
  packageRoot = pkgs.runCommand "sqlite-verifier-test-packages" {} ''
    mkdir -p "$out"
    ln -s ${leanToolchain} "$out/lean"
    ${pkgs.lib.concatStrings (pkgs.lib.mapAttrsToList (path: package: ''
      mkdir -p "$out/${path}"
      for entry in $(ls -A ${package}); do ln -s "${package}/$entry" "$out/${path}/$entry"; done
    '') leanPackages)}
  '';
  # The compiler and the built documentation tool, for the inventory's fixture tests.
  documentationRoot = pkgs.runCommand "sqlite-verifier-test-documentation" {} ''
    mkdir -p "$out/packages"
    ln -s ${leanToolchain} "$out/lean"
    ln -s ${leanPackages."packages/public-doc-tools"} "$out/packages/public-doc-tools"
  '';
  # `seeds`: Lake cache seeds (case-seeds.nix) copied into one writable cache that the tests use (ADR 0010).
  suite = name: { inputs, runtime, tools ? [], environment ? {}, seeds ? [] }:
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
        ${pkgs.lib.optionalString (seeds != [ ]) ''
          export BELAY_TEST_CACHE="$TMPDIR/lake-cache" BELAY_TEST_SEEDED=1
          mkdir -p "$BELAY_TEST_CACHE"
          for seed in ${pkgs.lib.concatStringsSep " " (map toString seeds)}; do
            cp -R --no-preserve=mode "$seed/." "$BELAY_TEST_CACHE/"
          done
        ''}
        timeout ${toString suiteTimeoutSeconds} python3 -m pytest ${file} ${pkgs.lib.concatStringsSep " " extraFiles} --runtime-root ${runtime} \
          -p no:cacheprovider -p pytest_timeout --timeout=${toString testTimeoutSeconds} \
          --junitxml "$out/junit.xml" -v --durations=10
      '';
    } // environment);
  # Locked frozen corpora (ADR 0011): each import of conformance.corpus reads the judge's claims.
  claims = root + /judge/claims.json;
  lockedCorpora = map (entry: root + "/${entry.path}")
    (builtins.attrValues (builtins.fromJSON (builtins.readFile claims)).corpora);
  # Mutants rebuild changed copies of the two Lean packages, so their suites read the
  # complete sources, without local build outputs in `.lake`.
  mutantInputs = modelInputs ++ map (package: fs.difference (root + "/packages/${package}")
    (fs.maybeMissing (root + "/packages/${package}/.lake"))) [ "belay-sqlite" "verifier-conformance" ];
  # Inputs shared by the three suites that the old single model suite contained.
  modelInputs = frontend ++ [
    claims
    (root + /tests/conformance_freeze_capture.py)
    (fs.fileFilter (file: file.hasExt "json") (root + /conformance/cases))
    (root + /packages/belay-sqlite/Belay/Sqlite/SqlExecution.lean)
    (root + /packages/belay-sqlite/Belay/Sqlite/Execution.lean) (root + /packages/belay-sqlite/Belay/Sqlite/LiteralData.lean)
    (root + /packages/verifier-conformance/VerifierConformance/Trace.lean)
    (root + /packages/verifier-conformance/VerifierConformance/Outputs.lean)
    (root + /packages/verifier-conformance/VerifierConformance/Native.lean)
    (root + /packages/verifier-conformance/VerifierConformance/Case.lean)
    (root + /packages/verifier-conformance/VerifierConformance/Predict.lean)
    (fs.fileFilter (file: file.hasExt "py" || file.hasExt "json") (root + /judge))
    (root + /packages/belay-sqlite/Belay/Sqlite/Laws.lean)
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
    "model_assertions" "model_cases" "model_check" "resolve_mutants" "replay_tiers" "native_workers"
    "execution_profile" "native_limits" "native_acquisition"
    "native_storage"
    "refresh_corpus" "requirement_cases" "requirement_coverage"
    "authored_cases" "authored_cases_queries" "authored_boundaries" "authored_review" "authored_report"
    "authored_transactions" "transaction_evidence" "authored_resolution" "resolution_evidence"
    "authored_queries" "query_evidence" "query_mutants" "authored_evidence" "authored_numbers" "number_evidence"
    "authored_writes" "write_evidence" "write_mutants"
    "number_mutants" "restriction_examples" "authored_obligations" "obligation_mutants" "obligation_evidence" "authored_row_writes" "row_write_evidence" "row_write_mutants" "authored_deletes" "delete_evidence" "delete_mutants" "authored_joins" "join_evidence" "join_mutants" "authored_using" "using_evidence" "using_mutants" "authored_right" "right_evidence" "right_mutants" "authored_merged" "merged_evidence" "merged_mutants" "authored_keys" "key_evidence" "key_mutants" "authored_aliases" "alias_evidence" "alias_mutants" "authored_upserts" "upsert_evidence" "upsert_mutants" "authored_algorithms" "algorithm_evidence" "algorithm_mutants" "authored_fromless" "fromless_evidence" "fromless_mutants" "authored_json" "json_evidence" "json_mutants" "authored_json_functions" "json_function_evidence" "json_function_mutants"
    "upstream_selection" "upstream_catalog" "upstream_sampling" "upstream_profiles" "upstream_functions" "upstream_result_values"
    "corpus_shards" "corpus_workers" "corpus_evidence" "corpus_acquisition" "locked_corpora" "freeze_corpus" "freeze_validation" "freeze_profiles" "workload" "workload_inputs"
    "upstream_assertions"
    "native_bindings" "native_call_recording" "native_binding_types" "native_binding_validation"
    "native_observation"
    "upstream_bindings" "upstream_binding_policy" "upstream_display" "upstream_evidence"
    "upstream_helpers"
    "native_fixture" "import_fixture" "schema" "predict" "predict_render" "replay_support"
    "case_format" "native_connection" "native_library" "native_clock" "native_probe" "native_ordering" "query_window" "native_metadata" "native_record" "native_statements" "native_replay" "profile_scope" "record_versions" "record_parser" "upstream_pilot" "upstream_fidelity" "corpus" "generated_program" "mutation_check" "state_machine" "regressions" "progress" "measure_coverage" "native_trace" "pipeline"
  ];
  # Frozen corpora and retained reports: large, rarely changed, read only by the frozen suite.
  frozenData = [
    (root + /conformance/corpus-v1)
    (root + /reports/20261001-adr5-c5-authored.json)
    (root + /reports/20261001-adr5-c5-authored-records.jsonl.gz)
    (root + /reports/20261006-grouped-immediate-transactions)
    (root + /conformance/corpus-v22)
    (root + /conformance/corpus-v21)
    (root + /conformance/corpus-v20)
    (root + /conformance/corpus-v19)
    (root + /conformance/corpus-v18)
    (root + /conformance/corpus-v17)
    (root + /conformance/corpus-v16)
    (root + /conformance/corpus-v15)
    (root + /conformance/corpus-v14)
    (root + /conformance/corpus-v13)
    (root + /conformance/corpus-v12)
    (root + /conformance/corpus-v11)
    (root + /conformance/corpus-v10)
    (root + /conformance/corpus-v9)
    (root + /conformance/corpus-v8)
    (root + /conformance/corpus-v7)
    (root + /conformance/corpus-v6)
    (root + /conformance/corpus-v5)
    (root + /conformance/corpus-v4)
    (root + /conformance/corpus-v3)
    (root + /conformance/corpus-v2)
  ];
  caseSeeds = import ./case-seeds.nix { inherit pkgs root; runtime = seedRuntime; };
  modelTools = [ native.sqlite native.sqlite346 native.sqlite3534 ];
in {
  sample = suite "sample" {
    inputs = frontend ++ [
      claims
      (root + /tests/native_worker_fixtures.py)
      (root + /conformance/corpus-v5)
      (root + /conformance/synthetic-workload)
    ] ++ map (name: root + "/conformance/${name}.py") [
      "replay_tiers" "native_workers" "corpus" "corpus_shards" "corpus_workers" "corpus_evidence" "corpus_acquisition" "locked_corpora" "case_format"
      "replay_support"
      "workload" "workload_inputs" "execution_profile" "native_limits" "native_replay" "profile_scope" "record_versions" "record_parser" "model_check"
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
  # Complete validation of the locked frozen corpora. The inputs are only the claims, the
  # corpora and the modules that the validation imports, so a change elsewhere reuses the
  # result. A module missing from this list fails the suite with an import error.
  corpora = suite "corpora" {
    inputs = frontend ++ [ claims ] ++ lockedCorpora ++ map (name: root + "/conformance/${name}.py") [
      "case_format" "corpus" "corpus_acquisition" "corpus_evidence" "corpus_shards" "corpus_workers" "replay_support"
      "execution_profile" "native_limits" "freeze_profiles" "freeze_validation" "model_assertions" "model_check"
      "native_acquisition" "native_binding_types" "native_binding_validation" "native_bindings"
      "native_call_recording" "native_clock" "native_connection" "native_library" "native_metadata"
      "native_observation" "native_record" "native_replay" "profile_scope" "record_versions" "native_statements" "native_storage"
      "native_trace" "native_workers" "locked_corpora" "query_window" "record_parser"
      "upstream_binding_policy" "upstream_bindings" "upstream_catalog" "upstream_helpers"
      "upstream_profiles" "upstream_result_values" "upstream_sampling"
    ];
    runtime = pkgs.emptyDirectory;
  };
  upstream = suite "upstream" {
    inputs = frontend ++ [
      (root + /tests/conformance_freeze_capture.py)
      (fs.fileFilter (file: file.hasExt "py" || file.hasExt "tcl") (root + /conformance))
      claims
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
  # The parser library: all grammars in one process and, on Linux, the sanitizer job.
  # Its runtime root holds the built inputs, so a harness or model change reuses the result.
  parserLibrary = suite "parserLibrary" {
    inputs = map (name: root + "/tests/${name}.py") [ "parser_inputs" "parser_library_inputs" "parser_library_support" ];
    runtime = parserLibrary;
  };
  atuin = suite "atuin" {
    inputs = caseReader;
    inherit runtime;
  };
  bundle = suite "bundle" {
    seeds = builtins.attrValues caseSeeds;
    inputs = [
      (fs.fileFilter (file: file.hasExt "py") (root + /migration_check))
      (fs.fileFilter (file: file.hasExt "py") (root + /belay/sqlite))
      (fs.fileFilter (file: file.hasExt "json") (root + /conformance/cases))
      (root + /tests/sql_fixtures.py)
      (root + /tests/example_cases.py)
      (root + /experiments/adr-0003-latency/cases.py)
      # cases.py reads the examples' belay.toml files; the runtime under test contains them too.
      # Regular files only: no `.belay` links of local proofs-project builds (ADR 0010).
      (fs.fileFilter (file: file.type == "regular" && file.name != ".DS_Store") (root + /examples))
      (root + /experiments/adr-0003-latency/stage_timing.py)
    ];
    inherit runtime;
  };
  cli = suite "cli" {
    inputs = caseReader;
    inherit runtime;
  };
  packages = suite "packages" {
    inputs = [ ];
    runtime = packageRoot;
  };
  documentation = suite "documentation" {
    inputs = [ (root + /tools/__init__.py) (root + /tools/public_doc_inventory.py) (root + /tools/public_doc_coverage.py)
               (root + /tests/public_doc_inventory) ];
    runtime = documentationRoot;
  };
  kernel = suite "kernel" {
    inputs = [ (fs.fileFilter (file: file.hasExt "lean") (root + /tests/kernel_gate)) (root + /tests/kernel_gate_support.py) ];
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
  mutants = suite "mutants" {
    inputs = mutantInputs;
    runtime = conformance;
    tools = modelTools;
  };
  # The round trips of the corpus writers of the authored cases; a scheduled suite.
  writers = suite "writers" {
    inputs = modelInputs;
    runtime = conformance;
    tools = modelTools;
  };
}
