#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
src=${1:-"$root/firmware/Bruce"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 "$root/tests/webui-control/extract.py" "$src/src/core/wifi/webInterface.cpp" "$tmp/webui-extracted.inc"
g++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined -fno-omit-frame-pointer -I"$tmp" "$root/tests/webui-control/control-test.cpp" -o "$tmp/control-test"
"$tmp/control-test"
python3 "$root/tests/webui-control/wiring-test.py" "$src"
