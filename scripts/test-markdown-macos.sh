#!/usr/bin/env bash
# Kiểm thử bộ render Markdown → chữ thuần cho bong bóng Siri trên macOS.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -I Sources \
  tests/markdown_test.m Sources/SXMarkdown.m -framework Foundation -o "$out/markdown_test"
"$out/markdown_test"
