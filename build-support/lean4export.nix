# Unpatched lean4export v4.34.0 supplies the exporter library and bundle parser.
{ pkgs }:
pkgs.fetchzip {
  url = "https://github.com/leanprover/lean4export/archive/076e8e57707e813375e8f9da8bf989799ace9680.tar.gz";
  hash = "sha256-sy3UivooYm1t1xdXu+/Fcq0x+U0V/6v19i1c/snnfFo=";
}
