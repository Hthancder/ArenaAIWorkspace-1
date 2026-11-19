#!/usr/bin/env bash
# So sánh phiên bản cho tính năng kiểm tra cập nhật (không cần mạng).
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -I Sources \
  tests/update_test.m Sources/SXUpdate.m Sources/SXHTTP.m Sources/SXLog.m \
  -framework Foundation -o "$out/update_test"
"$out/update_test"
