#!/usr/bin/env bash
# Kiểm thử ẩn khoá/token trong một dòng log trên macOS.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -I Sources \
  tests/log_redact_test.m Sources/SXLog.m -framework Foundation -o "$out/log_redact_test"
"$out/log_redact_test"
