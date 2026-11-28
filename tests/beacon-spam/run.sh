#!/usr/bin/env bash
# Beacon spam: SSID source, exact beacon counts, parallel deauth, channel sweep.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
src=${1:-"$root/firmware/Bruce"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$root/tests/beacon-spam/test.cpp" "$tmp/"
cp -r "$root/tests/beacon-spam/stubs" "$tmp/"
(cd "$tmp" && python3 "$root/tests/beacon-spam/prepare.py" "$src")
g++ -std=c++17 -Wall -Wextra -fsanitize=address,undefined -fno-omit-frame-pointer \
  -I"$tmp/stubs" -I"$tmp" "$tmp/test.cpp" -o "$tmp/t"
"$tmp/t"
