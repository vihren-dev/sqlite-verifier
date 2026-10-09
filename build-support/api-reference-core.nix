# The doc-gen4 database for Lean's own Init and Std libraries (ADR 0009).
# Its only inputs are the Lean toolchain and the pinned doc-gen4, and its commands are here,
# not in a repository script, so Nix and the CI cache reuse it until one of them changes.
{ pkgs, leanToolchain, docGen4 }:
pkgs.runCommand "sqlite-verifier-api-reference-core" {
  nativeBuildInputs = [ leanToolchain ];
} ''
  export HOME="$TMPDIR"
  cd "$TMPDIR"
  ${docGen4}/bin/doc-gen4 bibPrepass --build "$out" --none
  ${docGen4}/bin/doc-gen4 genCore --build "$out" Init api-docs.db
  ${docGen4}/bin/doc-gen4 genCore --build "$out" Std api-docs.db
''
