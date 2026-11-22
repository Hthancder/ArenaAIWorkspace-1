#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
source_dir=${1:-"$root/firmware/Bruce"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
g++ -std=c++17 -DBOARD_HAS_PSRAM -fsanitize=address,undefined -fno-omit-frame-pointer \
  -I"$root/tests/web-mirror/stubs" -I"$source_dir/include" -I"$source_dir/src" \
  "$source_dir/src/core/tftLogger/tftLogger.cpp" "$root/tests/web-mirror/logger-test.cpp" -o "$tmp/logger-test"
"$tmp/logger-test"
g++ -std=c++17 -fsanitize=address,undefined -fno-omit-frame-pointer \
  -I"$root/tests/web-mirror/stubs" -I"$source_dir/include" -I"$source_dir/src" \
  "$source_dir/src/core/tftLogger/tftLogger.cpp" "$root/tests/web-mirror/logger-test.cpp" -o "$tmp/logger-test-no-psram"
"$tmp/logger-test-no-psram"
node "$root/tests/web-mirror/render-test.js" "$source_dir/embedded_resources/web_interface/index.js"
g++ -std=c++17 -I"$source_dir/src" "$root/tests/web-mirror/nav-test.cpp" -o "$tmp/nav-test"
"$tmp/nav-test"
node "$root/tests/web-mirror/reload-test.js" "$source_dir/embedded_resources/web_interface/index.js"
node "$root/tests/web-mirror/timer-test.js" "$source_dir/embedded_resources/web_interface/index.js"
