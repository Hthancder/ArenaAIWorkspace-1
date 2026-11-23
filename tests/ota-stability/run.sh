#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
src=${1:-"$root/firmware/Bruce"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 "$root/tests/ota-stability/extract.py" "$src" "$tmp"
g++ -std=c++17 -Wall -Wextra -Werror -I"$tmp" "$root/tests/ota-stability/routes-test.cpp" -o "$tmp/routes-test"
"$tmp/routes-test"
g++ -std=c++17 -Wall -Wextra -Werror -I"$tmp" "$root/tests/ota-stability/ui-test.cpp" -o "$tmp/ui-test"
"$tmp/ui-test"
node "$root/tests/ota-stability/browser-test.js" "$src/embedded_resources/web_interface/index.js" "$src/src/core/wifi/webInterface.cpp"
