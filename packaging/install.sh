#!/bin/sh
# Install an extracted archive without downloading or weakening Nix signature checks.
set -eu
[ "$#" -eq 1 ] || { echo 'Usage: ./install.sh NEW_INSTALLATION_DIRECTORY' >&2; exit 1; }
bundle=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
[ ! -e "$1" ] || { echo 'Installation directory already exists' >&2; exit 1; }
case "$(uname -s):$(uname -m)" in
  Darwin:arm64) system=aarch64-darwin ;;
  Linux:x86_64) system=x86_64-linux ;;
  *) echo 'Unsupported operating system or architecture' >&2; exit 1 ;;
esac
[ "$system" = "$(cat "$bundle/platform")" ] || { echo 'Archive platform mismatch' >&2; exit 1; }
# Encode every path byte except slash so spaces, Unicode, percent and query markers stay inert.
cache_uri=$(printf '%s' "$bundle/nix-cache" | od -An -v -tx1 | awk '
  { for (i = 1; i <= NF; i++) if ($i == "2f") printf "/"; else printf "%%%s", toupper($i) }
')
nix --extra-experimental-features nix-command --offline copy --all --from "file://$cache_uri"
IFS= read -r python < "$bundle/python-path"
exec "$python" -I "$bundle/install.py" "$1"
