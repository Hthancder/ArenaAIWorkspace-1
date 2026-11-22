#!/usr/bin/env bash
# Kiểm thử bộ ẩn dữ liệu nhận dạng trước khi gửi AI trên macOS.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -I Sources \
  tests/anonymizer_test.m Sources/SXAnonymizer.m tests/log_stub.m -framework Foundation -o "$out/anonymizer_test"
"$out/anonymizer_test"
