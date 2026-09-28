# All project builds share the development environment's single reviewed pin.
{ system ? builtins.currentSystem }:
let
  lock = builtins.fromJSON (builtins.readFile ../nix/flake.lock);
  root = lock.nodes.${lock.root or "root"} or {};
  node = root.inputs.nixpkgs or null;
  locked = if builtins.isString node then lock.nodes.${node}.locked or {} else {};
  required = [ "type" "owner" "repo" "rev" "narHash" ];
  supported = (locked.type or null) == "github"
    && builtins.all (name: builtins.hasAttr name locked) required;
in
assert builtins ? fetchTree || throw "Project builds require Nix flakes/fetchTree enabled";
assert supported || throw "Unsupported nixpkgs lock: expected a direct locked GitHub input";
import (builtins.fetchTree (builtins.listToAttrs
  (map (name: { inherit name; value = locked.${name}; }) required))) { inherit system; }
