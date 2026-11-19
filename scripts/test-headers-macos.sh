#!/usr/bin/env bash
# Kiểm thử tầng header tuỳ chỉnh (validate/chuẩn hoá/bộ header gửi đi) trên macOS.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -I Sources \
  tests/headers_test.m Sources/SXHeaders.m -framework Foundation -o "$out/headers_test"
"$out/headers_test"
