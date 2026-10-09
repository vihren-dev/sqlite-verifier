# The SQLite parser library (see docs/sqlite-parser.md, "Parser library").
# Nix reads parser/dialects.json and makes one derivation for each release, one for each
# distinct grammar identity and one that links the library, so a new release or grammar
# builds only its own derivations. The `parserLibrary` suite of tests.nix checks the result.
{ pkgs, parsers, root ? ../. }:
let
  inherit (pkgs) lib;
  fs = lib.fileset;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  table = builtins.fromJSON (builtins.readFile (root + /parser/dialects.json));
  libraryName = "libsqlite-verifier-parser" + (if isLinux then ".so" else ".dylib");
  # Prefix of a grammar's symbols; parser/library_steps.py fails if two grammars share one.
  prefix = identity: "Syntax_" + builtins.substring 0 16 identity;
  # The build steps and the grammar transform; the release and grammar files come per derivation.
  steps = map (name: root + "/parser/${name}.py")
    [ "library_steps" "grammar_sources" "dialect_table" "library_metadata" "generate" ];
  source = files: fs.toSource { inherit root; fileset = fs.unions files; };
  releaseOf = version: lib.findFirst (release: release.version == version)
    (throw "parser/dialects.json has a dialect of release ${version}, which its release list does not name")
    table.releases;
  # Only this release and its dialects, so a new release leaves the other derivations unchanged.
  releaseTable = release: builtins.toFile "dialects-${release.version}.json" (builtins.toJSON {
    releases = [ release ];
    dialects = builtins.filter (dialect: dialect.version == release.version) table.dialects;
  });
  # Lemon's outputs for the release, after the hash and dialect identity checks.
  releaseBuild = release: let directory = "parser/${release.sources}"; in pkgs.stdenv.mkDerivation {
    pname = "sqlite-verifier-parser-release";
    inherit (release) version;
    src = source (steps ++ [ (root + "/${directory}") ]);
    nativeBuildInputs = [ pkgs.python3 ];
    dontConfigure = true;
    dontInstall = true;
    buildPhase = ''
      python3 -m parser.library_steps hashes ${directory}
      mkdir -p "$out"
      $CC ${directory}/lemon.c -o "$out/lemon"
      "$out/lemon" -q -d"$out" -T${directory}/lempar.c ${directory}/parse.y
      rm "$out/parse.c"
      "$out/lemon" -E ${directory}/parse.y > "$out/preprocessed.y"
      "$out/lemon" -g ${directory}/parse.y > "$out/grammar.y"
      python3 -m parser.library_steps release --directory ${directory} --table ${releaseTable release} \
        --preprocessed "$out/preprocessed.y" --output "$out/release.json"
    '';
  };
  releases = lib.listToAttrs (map (release: lib.nameValuePair release.version (releaseBuild release)) table.releases);
  # Each distinct identity, built from the first dialect's release; equal identities have equal sources.
  identities = lib.unique (map (dialect: dialect.grammar) table.dialects);
  releaseOfGrammar = identity:
    releaseOf (lib.findFirst (dialect: dialect.grammar == identity) null table.dialects).version;
  # The generated parser of one grammar, with its own symbol prefix and its production check.
  grammarSources = identity: let
    release = releaseOfGrammar identity;
    directory = "parser/${release.sources}";
    built = releases.${release.version};
  in pkgs.stdenv.mkDerivation {
    pname = "sqlite-verifier-parser-grammar";
    version = builtins.substring 0 16 identity;
    src = source (steps ++ map (name: root + "/${directory}/${name}") [ "lempar.c" "sqlite3.c" ]);
    nativeBuildInputs = [ pkgs.python3 ];
    dontConfigure = true;
    dontInstall = true;
    buildPhase = ''
      mkdir -p "$out"
      cp ${built}/preprocessed.y ${built}/grammar.y ${built}/parse.h "$out/"
      python3 parser/generate.py ${directory} "$out" --name ${prefix identity}
      ${built}/lemon -q -T${directory}/lempar.c "$out/syntax.y"
      python3 -m parser.library_steps grammar --directory "$out" --identity ${identity} --prefix ${prefix identity}
    '';
  };
  grammars = lib.genAttrs identities grammarSources;
  # The objects of one grammar: its tokenizer, with SQLite's symbols internal, and its parser.
  grammarObjects = flags: identity: let
    release = releaseOfGrammar identity;
    directory = "parser/${release.sources}";
  in pkgs.runCommandCC "sqlite-verifier-parser-objects-${builtins.substring 0 16 identity}" {
    src = source (map (name: root + "/parser/${name}")
      [ "runtime.h" "tokenizer.c" "library_prefix.h" "library_tokenizer.c" "library_grammar.c" ]
      ++ map (name: root + "/${directory}/${name}") [ "sqlite3.c" "sqlite3.h" ]);
  } ''
    mkdir -p "$out"
    for unit in library_tokenizer library_grammar; do
      $CC ${flags} -std=c99 -fPIC -fvisibility=hidden -c -DGRAMMAR_PREFIX=${prefix identity} \
        -I${grammars.${identity}} -I"$src/${directory}" -I"$src/parser" "$src/parser/$unit.c" -o "$out/$unit.o"
    done
  '';
  # Link all grammars with the API; the export check runs unless sanitizer runtimes add symbols.
  library = { name, flags, exportCheck }: let objects = map (grammarObjects flags) identities; in
    pkgs.runCommandCC name {
      src = source (steps ++ [ (root + /parser/library.c) (root + /parser/library.h) (root + /parser/runtime.h) ]);
      nativeBuildInputs = [ pkgs.python3 ];
    } ''
      cd "$src"
      work="$TMPDIR/library"
      mkdir -p "$work" "$out/lib" "$out/include"
      python3 -m parser.library_steps sources --table ${builtins.toFile "dialects.json" (builtins.toJSON table)} \
        ${lib.concatMapStringsSep " " (release: "--release ${releases.${release.version}}/release.json") table.releases} \
        ${lib.concatMapStringsSep " " (identity: "--grammar ${grammars.${identity}}/grammar.json") identities} \
        --output "$work"
      $CC ${flags} -std=c99 -fPIC -fvisibility=hidden -c -I"$work" -Iparser parser/library.c -o "$work/library.o"
      $CC ${flags} ${if isLinux then "-shared" else "-dynamiclib"} -o "$out/lib/${libraryName}" \
        ${lib.concatMapStringsSep " " (objects: "${objects}/*.o") objects} "$work/library.o" \
        ${lib.optionalString isLinux "-lm -lpthread -ldl"}
      ${lib.optionalString exportCheck ''python3 -m parser.library_steps exports "$out/lib/${libraryName}"''}
      cp parser/library.h "$out/include/sqlite-verifier-parser.h"
    '';
  # The sanitizer job's build; LeakSanitizer is part of AddressSanitizer on Linux.
  sanitizerFlags = "-O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined -fno-sanitize-recover=all";
  normal = library { name = "sqlite-verifier-parser-library"; flags = "-O1"; exportCheck = true; };
  sanitized = library { name = "sqlite-verifier-parser-library-sanitized"; flags = sanitizerFlags; exportCheck = false; };
  # Every parser test input and every distinct SQL text of every retained corpus.
  inputs = pkgs.runCommand "sqlite-verifier-parser-inputs" {
    src = source ([ (root + /tests/__init__.py) (root + /tests/parser_inputs.py) (root + /tests/parser_library_inputs.py) ]
      ++ map (version: root + "/conformance/corpus-v${toString version}") [ 1 2 3 4 5 ]);
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    cd "$src"
    python3 -m tests.parser_library_inputs --output "$out" \
      ${lib.concatMapStringsSep " " (version: "--corpus conformance/corpus-v${toString version}") [ 1 2 3 4 5 ]}
  '';
  driver = root + /tests/parser_library_driver.c;
in {
  inherit releases grammars inputs;
  library = normal;
  # The runtime root of the parserLibrary test suite: the library, the driver, the
  # executables for the comparison, the inputs and, on Linux, the sanitized build.
  testRoot = pkgs.runCommandCC "sqlite-verifier-parser-library-tests" {} ''
    mkdir -p "$out/bin" "$out/lib"
    ln -s ${normal}/lib/${libraryName} "$out/lib/${libraryName}"
    $CC -std=c99 -O1 ${driver} -o "$out/bin/parser-library-driver" ${lib.optionalString isLinux "-ldl"}
    ln -s ${parsers}/build "$out/build"
    ln -s ${inputs} "$out/inputs"
    ${lib.optionalString isLinux ''
      mkdir -p "$out/sanitized/bin" "$out/sanitized/lib"
      ln -s ${sanitized}/lib/${libraryName} "$out/sanitized/lib/${libraryName}"
      $CC -std=c99 ${sanitizerFlags} ${driver} -o "$out/sanitized/bin/parser-library-driver" -ldl
    ''}
  '';
} // lib.optionalAttrs isLinux { sanitizedLibrary = sanitized; }
