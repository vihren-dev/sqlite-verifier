# Select complete component inputs before converting any checkout path to the store.
{ lib, root ? ../. }:
let
  fs = lib.fileset;
  source = fileset: fs.toSource { inherit root fileset; };
  # Prune generated trees even when a developer creates them inside a component.
  clean = path: fs.unions (lib.mapAttrsToList (name: type:
    if builtins.elem name [ ".git" ".jj" ".lake" "build" "dist" "__pycache__" ] then fs.unions []
    else if type == "directory" then clean (path + "/${name}")
    else if type == "regular" then path + "/${name}" else fs.unions []) (builtins.readDir path));
  filtered = predicate: path: fs.intersection (clean path) (fs.fileFilter predicate path);
  extensions = names: filtered (file: builtins.any file.hasExt names);
in {
  unit = source (fs.unions [
    (extensions [ "py" ] (root + /tests))
    (extensions [ "py" ] (root + /migration_check))
    (extensions [ "py" ] (root + /parser))
    (extensions [ "py" ] (root + /packaging))
    (extensions [ "py" ] (root + /tools))
    (extensions [ "py" ] (root + /conformance))
    (root + /conformance/upstream/alter3.test)
    (root + /conformance/upstream/sha256.json)
    (root + /pytest.ini)
    (root + /build-support/run_unit_checks.py)
    (root + /build-support/unit-cases.json)
  ]);
  runtime = source (fs.unions [
    (extensions [ "py" ] (root + /migration_check))
    (filtered (file: file.name != ".DS_Store" && !file.hasExt "pyc") (root + /examples))
    (root + /LICENSE) (root + /docs/install.md)
    (root + /packaging/runtime_dependencies.py)
    (root + /packaging/write_runtime_roots.py)
    (root + /packaging/install.py) (root + /packaging/install.sh)
  ]);
  parsers = source (extensions [ "py" "c" "h" "y" "json" ] (root + /parser));
  lean = source (fs.unions [
    (fs.unions (map (name: root + "/${name}")
      (builtins.filter (name: lib.hasSuffix ".lean" name
        && (builtins.readDir root).${name} == "regular")
        (builtins.attrNames (builtins.readDir root)))))
    (extensions [ "lean" ] (root + /SqliteVerifier))
    (root + /lakefile.toml) (root + /lake-manifest.json) (root + /lean-toolchain)
  ]);
}
