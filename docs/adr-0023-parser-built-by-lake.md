# ADR 0023: Lake builds the parser library from committed C sources

Date: 2026-10-23. Status: PROPOSED.
Implementation: one task file and one pull request, after the owner accepts this ADR.
Audience: designers and reviewers.
Related: [ADR 0007](adr-0007-parser-library.md) (the parser library and its tests),
[ADR 0010](adr-0010-lake-builds-and-artifact-cache.md) (Lake builds, one Nix derivation per
Lean package), [ADR 0011](adr-0011-product-trust-and-development-integrity.md) (the judge's
subject), [ADR 0016](adr-0016-model-and-surface.md) ("Deferred": a separate repository for
the surface), [ADR 0017](adr-0017-user-surface.md) (D2: installing the surface with its native
library), [ADR 0020](adr-0020-local-build-loop.md) (the local build loop).

## Overview

The text package `packages/belay-sqlite-text` links the SQLite parser library, which only Nix
builds. Its lakefile reads the library's folder from the environment variable
`BELAY_PARSER_LIBRARY` and stops when the variable is not set. Thus every Lake build of the text
package or of the surface `belay` needs Nix and the variable: the Nix builds, the local loop,
the editor's server and each future user. This ADR makes Lake compile the parser library's C
code as part of the text package. Nix still generates the parser from the vendored SQLite
sources, and the generated C is committed. A Nix check makes sure that the committed C is what
the generation gives. Lake compiles the C with the C compiler of Lean's toolchain and a small
set of C library headers that the repository holds. After the change, a Lake build of the text
package needs only the pinned Lean: no system C compiler and no Nix.

## Context

### The problem: only Nix can build the parser library

The owner asked on 2026-10-23 for the parser library to be built by Lake, as the first step of
an install path for Lean users. Today a user who requires the surface must:

1. install Nix and build `parserLibrary.library` from a checkout of this repository;
2. set `BELAY_PARSER_LIBRARY` to the result in each shell that runs Lake, and in the
   environment of the editor;
3. keep that Nix store path alive, because the text package's shared libraries and the
   translation program find the library through a run-time search path into the store.

The usual way for a Lean package with C code is an `extern_lib` that Lake compiles. A user then
needs only `lake build`.

### Facts that constrain the design

1. **Nix builds the library in three stages** (`build-support/parser-library.nix`). For each
   release: a check of the hashes of the vendored sources, then Lemon (compiled from the
   release's `lemon.c`) and `parser/library_steps.py`. For each grammar identity:
   `parser/generate.py` and Lemon generate the parser. Last, the C compiler compiles the
   objects and links one shared library. The two first stages need Python 3 and a compiled
   Lemon. Only the last stage is C compilation.
2. **The C that the last stage compiles.** For each grammar: `parser/library_tokenizer.c`,
   which includes the release's 9 MB `sqlite3.c`, and `parser/library_grammar.c`, with the
   generated `syntax.c`, `syntax.h`, `parse.h`, `token_map.inc` and `token_names.inc`. For the
   whole library: `parser/library.c` with the generated `library_grammars.inc` and
   `library_metadata.inc`. With the two grammars of today, the generated files are 708 KB.
   Each grammar adds about 330 KB.
3. **Lean's toolchain has a C compiler but no C library headers.** The release archives of
   Lean 4.34.1 for Linux x86_64 and macOS aarch64 have `bin/clang`, a linker and `llvm-ar`.
   Their `include/` folder has only `lean/` and the compiler's own headers in `clang/`
   (`stddef.h`, `stdint.h`, `stdarg.h`, `float.h` and similar). There is no `stdio.h`. The
   libraries that Lean links into each program are in the archive: glibc in `lib/glibc` on
   Linux, `lib/libc/libSystem.tbd` on macOS. Lake's `buildO`, which compiles a C file that is
   not Lean output, calls `cc` by default. `buildLeanO` calls Lean's `clang` with Lean's flags,
   which include `-nostdinc` and the toolchain as the system root (`Lake/Build/Common.lean` and
   `Lake/Build/Actions.lean`). The Nix build of the repository uses the same release archives
   (`build-support/lean-toolchain.nix`).
4. **The C compiles fast.** Measured on 2026-10-23 on one Linux x86_64 host (8 CPUs, load
   average 0.5), with GCC 15.3 and the flags of the Nix build (`-O1 -std=c99 -fPIC
   -fvisibility=hidden`): `library_tokenizer.c` for 3.51.0 in 0.62 s with 102 MB of memory,
   for 3.46.0 in 0.58 s, and `library_grammar.c` for 3.51.0 in 0.56 s. The tokenizer includes
   all of `sqlite3.c`, but the macros of `library_tokenizer.c` make SQLite's functions static,
   and the compiler drops what the tokenizer does not use.
5. **A trial build worked.** On 2026-10-23, in a copy of the model and text packages, the
   text package's lakefile was changed so that `buildO` compiles the five C units of fact 2 from
   the Nix-generated files. The units and the shim go into one static `extern_lib`. The
   `-L`, `-l` and run-time search path arguments were removed. With `BELAY_PARSER_LIBRARY` not
   set:
   - `lake build BelaySqliteText BelaySqliteText:shared parserShim:shared
     belay-sqlite-translate` passed (632 jobs, 42 s). From clean, the C part took 4 jobs and
     1.4 s.
   - The translation program links no parser library: `ldd` shows only glibc's libraries.
     Its shared library for the precompiled modules is 219 KB; the Nix-built parser library
     is 221 KB.
   - For all 11,118 distinct SQL texts of the parser's test inputs and of corpora v1 to v5
     (`parserLibrary.inputs`), under the three profiles 3.51.0, 3.46.0 and 3.53.4 (33,354
     requests), the trial program and the current program gave byte-identical answers.
     3.53.4 has no grammar, so both refuse those requests with the same message. The trial
     did not use the texts of the later corpora; the predictions test of D5 covers them.
   - `lake lean` of a file with `#eval Belay.Sqlite.ParserLibrary.metadata` printed the
     library's metadata. Elaboration called the parser through the precompiled modules.
6. **The C needs few C library declarations.** With the SQLite options `SQLITE_OS_OTHER=1`
   (no operating system layer) and `SQLITE_THREADSAFE=0` (no mutexes), the five units include
   only these C library headers: `assert.h`, `ctype.h`, `math.h`, `stdio.h`, `stdlib.h`,
   `string.h` and `time.h`. Compiled at `-O1`, the objects call only ten C library functions:
   `calloc`, `fprintf`, `free`, `fwrite`, `malloc`, `memcpy`, `realloc`, `snprintf`, `strcmp`
   and `strlen`. The tokenizer objects call none. SQLite expects an application with
   `SQLITE_OS_OTHER` to define `sqlite3_os_init` and `sqlite3_os_end`. The compiler warns that
   they are not defined, and drops the code that calls them, because the tokenizer does not
   use it.
7. **A second trial compiled with Lean's compiler.** On 2026-10-23, the lakefile of fact 5 was
   changed to compile the units with `buildLeanO`, the two options of fact 6, and one folder of
   seven headers with 37 lines in total. The headers declare the C library functions that the
   units use, with their standard signatures. `FILE` is an incomplete type, and `struct tm` has a complete
   definition with the members that `sqlite3.c` uses. Lake ran with a `PATH` that had
   no `cc`, `gcc` or `clang`.
   - The build of fact 5 passed. From clean, the C part took 1.4 s (8 CPUs, load average 6.6).
   - For the 33,354 requests of fact 5, the answers were byte-identical to those of the
     current program.
   - The elaboration check of fact 5 passed.
8. **A Nix workspace holds only the package folders.** `sources.text` has the package folder
   as its root, and `build-support/lean-package.nix` copies it to its path in a copy of the
   repository layout, with the outputs of the required packages at their paths. The output of
   a package is its folder only. The surface's build replays the text package's output in its
   own workspace, and Lake checks the inputs of each target that it replays. Files outside
   the package folders, such as `parser/`, are in no workspace unless a derivation copies
   them there.
9. **Other users of the parser library.** The `parserLibrary` suite of `tests.nix` loads the
   Nix-built shared library: the comparison of each grammar with the corpora, the sanitizer
   job on Linux, the load test and the export check. `tests/surface_parser_test.py` checks
   the error when the shared library is missing. `shell.nix` sets `BELAY_PARSER_LIBRARY`, and
   the recipes and the test of the local loop use it to find out whether the shell is loaded
   (ADR 0020, D4 and D6).
10. **What other Lean packages do.** On 2026-10-23, the lakefiles of Lean packages with C code
    on GitHub showed three ways (see "Sources"):
    - Most compile vendored C with `buildO` or `compileO` and the system `cc`: `leansqlite`
      (the SQLite amalgamation), `nauty-ffi`, `CMark.lean` and `md4lean`, which doc-gen4
      requires. The README of `leansqlite` says that the build "requires a C compiler called
      `cc` on the `PATH`". Its lakefile disables SQLite's large file support because "Lean's
      bundled libc only provides fcntl and not fcntl64".
    - Some use Lean's `clang` with other headers. On Windows, `md4lean` adds its own
      `stdio.h`, `stdlib.h` and `string.h`. `lean-beam` removes `-nostdinc` and the system
      root from Lean's flags and uses the headers of the host, from `xcrun --show-sdk-path` on
      macOS.
    - `LeanCopilot` and `lean-egg` download prebuilt libraries from their GitHub releases
      (`preferReleaseBuild`), because their native parts need CMake or Cargo.

## Decision

### D1. The generated C is committed under `parser/generated/`

The C files that the last stage compiles and that a generator writes (fact 2) are committed
under `parser/generated/`: one folder per grammar, named by the 16 hexadecimal digits of the
grammar's symbol prefix, and the two library files at the top of the folder. A manifest in the
same folder lists each grammar's prefix and the source folder of its release. The generation
stays in Nix, with its hash and identity checks, and does not change.

A recipe, `just parser-sources`, builds the generated files with Nix and writes them into the
checkout. A change to `parser/dialects.json`, to a vendored release or to a generator runs it,
and the change commits the result.

### D2. Lake compiles the parser library in the text package

The text package's lakefile compiles the C units of fact 2 with `buildLeanO`, that is, with
Lean's `clang` and Lean's flags (fact 3). It adds the flags of the Nix build, the two options of
fact 6, and the headers of `parser/c-headers/` as the system headers. It reads the grammars from
the manifest of D1, so a new grammar changes no Lean code.

`parser/c-headers/` declares only what the five units use (fact 6). Each function has its
standard C signature, because the linker resolves it in the C library that Lean links (fact
3), and a wrong declaration compiles and links without an error. A type that the source uses
only through pointers, such as `FILE`, stays incomplete. A type whose members the source uses,
such as `struct tm` in `sqlite3.c`'s date functions, gets a complete definition, because the
compiler checks the source before it drops unused code. Its layout can differ from the C
library's, because no kept code calls a C library function with it; the symbol test of D5
makes sure of that. `parser/library_tokenizer.c` defines `sqlite3_os_init` and
`sqlite3_os_end` as functions that return `SQLITE_OK` (fact 6), so that the compile gives no
warnings. A new SQLite release that needs more declarations adds them here, and the symbol
test of D5 shows which functions it calls.

The units and the shim go into one static `extern_lib`, which Lake also makes as a shared
library for the precompiled modules (fact 5). The lakefile does not read
`BELAY_PARSER_LIBRARY` and adds no linker arguments for the parser.

The text package refers to the C sources by their path in the repository: `parser/` for the
C files and the vendored releases, and `parser/generated/` for D1. Each Nix workspace that
builds or replays the text package has these files at the same paths (fact 8): the text
package's own build, the surface's build, and the build of any later package that requires
the text package. `lean-package.nix` gets a parameter for such extra source paths, and the
text package's dependents pass the same set. A git require with `subDir` gets the whole
repository, so the paths are there too.

The `extern_lib` gets a name for what it now holds, for example `parserLibrary`. The target
lists of the Nix build and of ADR 0020's D2 change with it.

### D3. One copy of the C for all builds

Nix's `parserLibrary.library` and its sanitized build compile the committed files of D1, not
the outputs of the generation. They use the headers and the options of D2. The library uses
Lean's `clang` from the pinned toolchain, as Lake does. The sanitized build keeps its own
compiler and adds its sanitizer flags. The manifest of D1 holds the compile flags, and the
lakefile and `parser-library.nix` read them from it. The `parserLibrary` suite then checks the
C that Lake compiles into the text package, as Lake compiles it. A new Nix check compares the committed files with a fresh generation,
byte for byte, and names each file that differs.

The Nix build of the text package is the judge's subject (ADR 0011). Its translation program
now contains the parser that Lake compiled from the committed files. The check of this section
ties those files to the vendored sources and their hashes.

### D4. Nothing sets `BELAY_PARSER_LIBRARY`

The variable goes away from `build-support/default.nix`, `shell.nix`, the lakefiles, the
READMEs of `belay` and `belay-sqlite-text`, and the docstrings. The recipes and the test of
the local loop find out whether the shell is loaded from another variable that `shell.nix`
sets. The test of a missing parser library in `tests/surface_parser_test.py` goes, because no
separate library can be missing.

### D5. Tests

- **The Nix builds without the variable.** The text package, the surface and the conformance
  runtime build with no `BELAY_PARSER_LIBRARY` in any environment.
- **The generation check of D3.** It passes on the commit. A change of one byte in a committed
  file makes it fail with that file's name; the task records this once.
- **The `parserLibrary` suite** passes on the library compiled from the committed files.
- **No parser library at run time.** A test reads the dynamic dependencies of the translation
  program and of the text package's shared libraries (`ldd` or `otool -L`) and checks that
  none is a parser library. This tests our link configuration.
- **The C library functions.** A test lists the undefined symbols of each object that the
  text package compiles from the C of D1. Each symbol that is not defined by another object of
  the library must be in a committed list: the ten functions of fact 6. The list has a comment
  that says why each function is safe to declare in `parser/c-headers/`. This tests our headers:
  a new function in the list needs a review of its declaration.
- **No system C compiler.** The Nix build of the text package runs Lake with a `PATH` that has
  no `cc`, `gcc` or `clang`.
- **The same predictions.** `just verdict` passes. The pull request records that the
  predictions for all corpora are byte-identical to those of trunk.
- **The local loop.** The test of ADR 0020, D6, passes in the shell without the variable.

The owner checks the build on macOS.

## Consequences

- **A Lake build of the text package or the surface needs only the pinned Lean.** It needs
  no system C compiler, no C library headers and no Xcode command line tools. A clean build
  compiles the C in about 1.5 s (facts 5 and 7). Most Lean packages with C code need `cc`
  (fact 10); this one does not.
- **The repository maintains its own C library declarations.** They are few (fact 6), and the
  test of D5 shows each new function that a new SQLite release calls.
- **The parser runs with `SQLITE_OS_OTHER` and `SQLITE_THREADSAFE=0`.** The tokenizer does not
  use the operating system layer or the mutexes. The `parserLibrary` suite and the predictions
  test check the parser with these options.
- **The editor needs no setup.** The editor's server loads the text package's shared
  libraries, which contain the parser.
- **The repository holds about 700 KB of generated C.** Each new SQLite release adds about
  330 KB. A diff of a grammar change shows the generated files too.
- **The conformance runtime no longer needs the parser library's store path at run time.**
- **Two builds compile the same C.** Nix compiles it for the `parserLibrary` suite and Lake
  compiles it for the text package. Both use the files, the headers and the flags of D1 and
  D2, with the same compiler.
- **The text package depends on the repository layout.** It reaches `parser/` with a relative
  path. A separate repository for the surface (ADR 0016, "Deferred") must bring these files
  (owner decision 2).

## Alternatives considered

**Keep the Nix-built library and the variable.** Rejected. It is the problem: each Lake build
needs Nix, and each user needs a store path.

**Generate the parser in Lake.** Lake would compile Lemon and run `parser/generate.py` and
`parser/library_steps.py`. Rejected. Each user would need Python 3, and the generation would
run on the user's machine without the hash checks of Nix.

**Compile with the system `cc` (`buildO`).** This was the first proposal, and most Lean packages
do it (fact 10). Rejected. Many machines have no C compiler, for example a macOS machine
without the Xcode command line tools, and the build then fails for a reason that the user cannot
see in Lean. The first trial (fact 5) shows that it works where `cc` exists.

**Compile with Lean's `clang` and the host's headers, as `lean-beam` does.** Rejected. It still
needs the C library headers of the host, from a development package or the Xcode command line
tools.

**Download prebuilt libraries for each platform from a release (`preferReleaseBuild`).**
Rejected for now. It needs a release for each platform, and Lake must still build from
source where no archive matches. The packages that do it need tools that a user does not have
(fact 10); this build needs none, and the C compiles in about 1.5 s. It can come back as a
speed-up if the C becomes slow to compile.

**Move the C sources and the vendored releases into the text package now.** Not chosen. It
makes the package self-contained, but it moves 20 MB of vendored sources and changes the
paths in the generators, `parser/dialects.json`, the tests and the docs. A git require gets
the whole repository, so a present problem does not need it. Owner decision 2 moves the
files at the split of the repository.

**A separate repository for the parser.** Rejected. A grammar change changes the generated C,
the grammar identity, the translation in the text package, the predictions and the corpora in
one change. With two repositories, each such change is two pull requests and a pinned revision,
and the checks of D3 must fetch the other repository. Only the text package and our tests use
the C library.

**Copy only the tokenizer code out of `sqlite3.c`.** Rejected. ADR 0007 uses SQLite's own
tokenizer from the release's `sqlite3.c`, and the grammar identity covers that code. A copy
would need its own check, and the compile time does not need it (fact 4).

## Not decided here

- The first release of the surface, its repository, its tags and a Reservoir entry (ADR 0016
  and ADR 0017, D2).
- A test in which a new project with only elan requires the surface by git and builds it. It
  comes with the release.
- User documentation for installing the surface.
- Platforms other than Linux x86_64 and macOS on Apple Silicon.

## Owner decisions

1. **This part comes before the first release.** ADR 0017, D2, keeps the install of the
   surface with its native library for the first release. This ADR takes the build of the
   native library out of that item, because the owner asked for it; the rest of the item stays.
   ADR 0017 gets an amendment that says so.
2. **The place of the C sources (D2).** Decided by the owner on 2026-10-23:
   - Until the first release, the C sources stay in `parser/` in this repository, and the
     text package reaches them by their path.
   - At the split of the surface into its own repository (ADR 0016, "Deferred"), the files
     that Lake compiles move into the text package in that repository: the generated C of D1,
     `parser/c-headers/`, the C files of `parser/`, and each release's `sqlite3.c` (about 9 MB
     each, 2.4 MB compressed). The generators, Lemon, the grammar files and the corpora stay
     in this repository. A Lean user then does not clone this repository, which is 116 MB
     without its history, because Lake clones each git dependency in full
     (`Lake/Util/Git.lean`).
   - The parser does not get a repository of its own (see "Alternatives considered").

## Sources

- Lake's C compile functions: `buildO`, `buildLeanO` and `compileO` in
  [`src/lake/Lake/Build/Common.lean`](https://github.com/leanprover/lean4/blob/v4.34.1/src/lake/Lake/Build/Common.lean)
  and [`src/lake/Lake/Build/Actions.lean`](https://github.com/leanprover/lean4/blob/v4.34.1/src/lake/Lake/Build/Actions.lean).
- Lake's clone of a git dependency: `clone` in
  [`src/lake/Lake/Util/Git.lean`](https://github.com/leanprover/lean4/blob/v4.34.1/src/lake/Lake/Util/Git.lean).
- The lakefiles of fact 10, read on 2026-10-23:
  [leanprover/leansqlite](https://github.com/leanprover/leansqlite) (lakefile and README),
  [leanprover/nauty-ffi](https://github.com/leanprover/nauty-ffi),
  [xubaiw/CMark.lean](https://github.com/xubaiw/CMark.lean),
  [acmepjz/md4lean](https://github.com/acmepjz/md4lean) (lakefile and `md4c/adhoc_include`),
  [leanprover/lean-beam](https://github.com/leanprover/lean-beam),
  [lean-dojo/LeanCopilot](https://github.com/lean-dojo/LeanCopilot) and
  [marcusrossel/lean-egg](https://github.com/marcusrossel/lean-egg).
