# Assemble immutable runtime artifacts for trusted source execution.
{ pkgs, sources, leanToolchain, parserLibrary, leanRuntime, modelPackage }:
let
  python = pkgs.python3;
  runtimePath = pkgs.lib.makeBinPath [ python ];
in pkgs.stdenv.mkDerivation {
  pname = "sqlite-verifier-runtime";
  version = "1";
  src = sources.runtime;
  nativeBuildInputs = [ python leanToolchain ];
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  dontPatchShebangs = true; # Installer must bootstrap before Nix paths exist.
  installPhase = ''
    mkdir -p "$out"
    cp -R . "$out/"
    cp -R ${sources.lean}/. "$out/"
    mkdir -p "$out/lib"
    cp ${parserLibrary}/lib/* "$out/lib/"
    cp -R ${leanRuntime}/.lake "$out/"
    mkdir -p "$out/packages"
    cp -R ${modelPackage} "$out/packages/belay-sqlite"
    chmod -R u+w "$out"
    ln -s ${leanToolchain} "$out/lean"
    echo '${python}/bin/python3' > "$out/python-path"
    echo '${pkgs.stdenv.hostPlatform.system}' > "$out/platform"
    mkdir -p "$out/bin"
    cat > "$out/bin/migration-check" <<'PY'
#!${python}/bin/python3 -I
"""Execute the immutable runtime with explicit tools and isolated imports."""
import os
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[1]
os.environ["MIGRATION_CHECK_LEAN_SYSROOT"] = str(root / "lean")
os.environ["PATH"] = "${runtimePath}"
sys.path.insert(0, str(root))
from migration_check.cli import main
raise SystemExit(main(sys.argv[1:]))
PY
    chmod +x "$out/bin/migration-check"
  '';
}
