#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
src=${1:-"$root/firmware/Bruce"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
g++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined -fno-omit-frame-pointer -DDSOLUTION_183_2MIC \
  -I"$root/tests/device-ux/stubs" -I"$src/src" \
  "$src/src/core/dsolution_ux.cpp" "$root/tests/device-ux/audio-test.cpp" -o "$tmp/audio-test"
"$tmp/audio-test"
g++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined -fno-omit-frame-pointer -DDSOLUTION_183_2MIC \
  -I"$root/tests/device-ux/stubs" -I"$src/src" \
  "$src/src/core/menu_items/QuickMenu.cpp" "$root/tests/device-ux/quick-test.cpp" -o "$tmp/quick-test"
"$tmp/quick-test"
node "$root/tests/device-ux/web-test.js" "$src/embedded_resources/web_interface/index.js" "$src/embedded_resources/web_interface/index.html"

node "$root/tests/device-ux/file-ux-test.js" "$src/embedded_resources/web_interface/index.js"
