# The SQLite parser library and its checks (see docs/sqlite-parser.md, "Parser library").
# Each attribute is a separate derivation, so CI reuses each result until its inputs change.
{ pkgs, sources, parsers, root ? ../. }:
let
  fs = pkgs.lib.fileset;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  libraryName = "libsqlite-verifier-parser" + (if isLinux then ".so" else ".dylib");
  # The sanitizer job of the library and its driver; LeakSanitizer is part of AddressSanitizer on Linux.
  sanitizerFlags = "-O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined -fno-sanitize-recover=all";
  # Only the check tools and the retained corpora; no harness code, model or documentation.
  checkSources = fs.toSource {
    inherit root;
    fileset = fs.unions [
      (root + /tests/__init__.py) (root + /tests/parser_inputs.py)
      (root + /tests/parser_library_inputs.py) (root + /tests/parser_library_check.py)
      (root + /tests/parser_library_driver.c)
    ];
  };
  corpora = fs.toSource {
    inherit root;
    fileset = fs.unions (map (version: root + "/conformance/corpus-v${toString version}") [ 1 2 3 4 5 ]);
  };
  build = { pname, cflags, exportCheck }: pkgs.stdenv.mkDerivation {
    inherit pname;
    version = "1";
    src = sources.parsers;
    nativeBuildInputs = [ pkgs.python3 ];
    dontConfigure = true;
    dontInstall = true;
    dontStrip = !exportCheck;
    buildPhase = ''
      python3 -m parser.library_build --output "$out" --work "$TMPDIR/library" \
        --cflags=${pkgs.lib.escapeShellArg cflags} ${pkgs.lib.optionalString (!exportCheck) "--no-export-check"}
    '';
  };
  # Run one check of tests/parser_library_check.py with a driver built with cflags.
  check = name: { library, cflags, arguments, environment ? "" }: pkgs.runCommandCC "sqlite-verifier-parser-${name}" {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    cd ${checkSources}
    $CC -std=c99 ${cflags} tests/parser_library_driver.c -o "$TMPDIR/driver" ${pkgs.lib.optionalString isLinux "-ldl"}
    ${environment}
    python3 -m tests.parser_library_check ${name} --driver "$TMPDIR/driver" \
      --library ${library}/lib/${libraryName} ${arguments} > "$TMPDIR/report"
    cat "$TMPDIR/report"
    mkdir -p "$out"
    cp "$TMPDIR/report" "$out/report.txt"
  '';
  library = build { pname = "sqlite-verifier-parser-library"; cflags = "-O1"; exportCheck = true; };
  # Every parser test input and every distinct SQL text of every retained corpus.
  inputs = pkgs.runCommand "sqlite-verifier-parser-inputs" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    cd ${checkSources}
    python3 -m tests.parser_library_inputs --output "$out" \
      ${pkgs.lib.concatMapStringsSep " " (version: "--corpus ${corpora}/conformance/corpus-v${toString version}") [ 1 2 3 4 5 ]}
  '';
  sanitizedLibrary = build {
    pname = "sqlite-verifier-parser-library-sanitized";
    cflags = sanitizerFlags;
    exportCheck = false;
  };
in {
  inherit library inputs;
  load = check "load" { inherit library; cflags = "-O1"; arguments = ""; };
  # One-time evidence that the library gives the executables' output; it ends with the executables.
  compare = check "compare" {
    inherit library;
    cflags = "-O1";
    arguments = "--inputs ${inputs} --executables ${parsers}/build";
  };
} // pkgs.lib.optionalAttrs isLinux {
  inherit sanitizedLibrary;
  sanitizer = check "sanitize" {
    library = sanitizedLibrary;
    cflags = sanitizerFlags;
    arguments = "--inputs ${inputs}";
    environment = ''
      export ASAN_OPTIONS=detect_leaks=1:halt_on_error=1
      export UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1
    '';
  };
}
