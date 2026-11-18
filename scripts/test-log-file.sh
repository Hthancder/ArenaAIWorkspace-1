#!/usr/bin/env bash
# Chạy regression file log thật trên Linux/macOS; không cần iOS SDK.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -I Sources tests/log_file_test.c -o "$out/log_file_test"
"$out/log_file_test"
