#!/usr/bin/env bash
# Kiểm thử tầng công cụ (registry/validate/cache/timeout) trên macOS Foundation.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -I Sources \
  tests/toolkit_test.m Sources/SXToolkit.m -framework Foundation -o "$out/toolkit_test"
"$out/toolkit_test"
