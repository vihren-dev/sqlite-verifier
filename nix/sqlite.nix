# Native engines shared by the development shell and test checks.
{ pkgs }:
let
  sqliteRelease = version: year: number: sha256: pkgs.stdenv.mkDerivation {
    pname = "sqlite-verifier-native";
    inherit version;
    src = pkgs.fetchurl {
      url = "https://sqlite.org/${year}/sqlite-autoconf-${number}.tar.gz";
      inherit sha256;
    };
    preConfigure = "patchShebangs configure";
    configureFlags = [ "--disable-readline" ];
    meta.license = pkgs.lib.licenses.publicDomain;
  };
in {
  sqlite = sqliteRelease "3.51.0" "2025" "3510000"
    "42e26dfdd96aa2e6b1b1be5c88b0887f9959093f650d693cb02eb9c36d146ca5";
  sqlite346 = (sqliteRelease "3.46.0" "2024" "3460000"
    "6f8e6a7b335273748816f9b3b62bbdc372a889de8782d7f048c653a447417a7d").overrideAttrs {
      postInstall = "mv $out/bin/sqlite3 $out/bin/sqlite3-3.46.0";
    };
}
