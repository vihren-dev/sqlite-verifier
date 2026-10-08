# Put the checked commit into the source links of the reusable base reference.
{ pkgs, base, revision }:
let
  tools = pkgs.runCommand "api-reference-link-tools" { } ''
    mkdir -p "$out/tools"
    cp ${../tools/source_revision.py} "$out/tools/source_revision.py"
    cp ${../tools/api_reference.py} "$out/tools/api_reference.py"
    cp ${../tools/api_reference_links.py} "$out/tools/api_reference_links.py"
  '';
  # tests/test_api_reference.py links this Nix guard to the shared Python policy.
  fullCommitHashPattern = "[0-9a-f]{40}";
in
assert builtins.isString revision && builtins.match fullCommitHashPattern revision != null;
pkgs.runCommand "sqlite-verifier-api-reference-${builtins.substring 0 12 revision}" {
  nativeBuildInputs = [ pkgs.python3 ];
} ''
  python3 ${tools}/tools/api_reference_links.py --base ${base} --output "$out" \
    --revision ${pkgs.lib.escapeShellArg revision}
''
