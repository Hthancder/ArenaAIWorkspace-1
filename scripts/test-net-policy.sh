#!/usr/bin/env bash
# Chạy regression chính sách mạng (web_fetch chặn mạng nội bộ) trên Linux/macOS.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -I Sources tests/net_policy_test.c -o "$out/net_policy_test"
"$out/net_policy_test"
