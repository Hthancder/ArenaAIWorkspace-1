#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
export SIRIX_TEST_STORE_DIR="$out/store"
clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -I Sources tests/store_test.m Sources/SXStore.m -framework Foundation -o "$out/store_test"
"$out/store_test"
