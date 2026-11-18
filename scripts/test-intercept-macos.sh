#!/usr/bin/env bash
# Foundation/Objective-C test của state machine thật, chạy trên macOS.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
export SIRIX_TEST_STORE_DIR="$out/store"
clang -DSX_TESTING=1 -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -Wno-incomplete-implementation -I Sources \
  tests/intercept_test.m Sources/SXIntercept.m Sources/SXDisplayPolicy.m Sources/SXStore.m Sources/SXToolkit.m \
  -framework Foundation -o "$out/intercept_test"
"$out/intercept_test"
