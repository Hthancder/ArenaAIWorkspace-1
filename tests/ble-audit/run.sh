#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
source_dir=${1:-"$root/firmware/Bruce"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
g++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined -fno-omit-frame-pointer \
  -I"$source_dir/src" "$root/tests/ble-audit/evidence-test.cpp" -o "$tmp/evidence-test"
"$tmp/evidence-test"
