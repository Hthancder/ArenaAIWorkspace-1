#!/usr/bin/env bash
# Kiểm thử vòng gọi công cụ + stream của SXLLM trên macOS (HTTP giả, không mạng).
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
clang -DSX_TESTING=1 -DSX_TEST_USE_REAL_PREFS=1 -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -Wno-incomplete-implementation \
  -I Sources \
  tests/sxllm_mock_test.m Sources/SXLLM.m Sources/SXStream.m Sources/SXToolkit.m Sources/SXHeaders.m \
  -framework Foundation -o "$out/sxllm_mock_test"
"$out/sxllm_mock_test"
