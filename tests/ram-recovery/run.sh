#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
src=${1:-"$root/firmware/Bruce"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
g++ -std=c++17 -Wall -Wextra -Werror -DDSOLUTION_183_2MIC -DBOARD_HAS_PSRAM -I"$root/tests/ram-recovery/mocks" -I"$src/src" "$root/tests/ram-recovery/radio-test.cpp" -o "$tmp/radio-test"
"$tmp/radio-test"
python3 "$root/tests/ram-recovery/wiring-test.py" "$src"
