#!/usr/bin/env bash
# Explicit live check of the pinned CI client and authenticated signed downloads.
set -euo pipefail
: "${ATTIC_READ_TOKEN:?Provide a read-only Attic token}"
: "${ATTIC_WRITE_TOKEN:?Provide an upload token}"
umask 077
temporary=$(mktemp -d)
temporary=$(cd "$temporary" && pwd -P)
trap 'rm -rf "$temporary"' EXIT
export XDG_CONFIG_HOME="$temporary/config"
attic=$(nix-build --expr '(import ./build-support/locked-nixpkgs.nix {}).attic-client' --no-out-link)
"$attic/bin/attic" login vihren https://cache.vihren.dev "$ATTIC_WRITE_TOKEN"
printf 'machine cache.vihren.dev login token password %s\n' "$ATTIC_READ_TOKEN" > "$temporary/netrc"
printf 'CI cache round trip: %s\n' "$temporary" > "$temporary/probe"
output=$(nix-store --add "$temporary/probe")
printf '%s\n' "$output" | "$attic/bin/attic" push vihren:sqlite-verifier --stdin
key='sqlite-verifier:tbKquH1YWJZFbMzT6Z14DmJ5yeVMnHSYobIDGdkWGis='
nix copy --from https://cache.vihren.dev/sqlite-verifier --to "$temporary/store" \
  --option netrc-file "$temporary/netrc" --option trusted-public-keys "$key" "$output"
nix store verify --store "$temporary/store" --all --sigs-needed 1 \
  --option trusted-public-keys "$key"
cmp "$temporary/probe" "$temporary/store$output"
test "$(curl --silent --show-error --max-time 15 -o /dev/null -w '%{http_code}' \
  https://cache.vihren.dev/sqlite-verifier/nix-cache-info)" = 401
echo 'Attic authenticated upload, signed download, and anonymous denial passed.'
