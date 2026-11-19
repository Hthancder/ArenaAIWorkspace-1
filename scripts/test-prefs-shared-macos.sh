#!/usr/bin/env bash
# Kiểm thử phần dùng chung của SXPrefs — chốt chặn cho lỗi "khai báo mà thiếu
# thân hàm" từng làm Settings văng ở 1.1.10–1.1.12.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
clang -DSX_TESTING=1 -DSX_TEST_USE_REAL_PREFS=1 -fobjc-arc -Wall -Wextra -Werror \
  -Wno-unused-parameter -Wno-incomplete-implementation -I Sources \
  tests/prefs_shared_test.m Sources/SXPrefsShared.m Sources/SXHeaders.m Sources/SXLog.m \
  -framework Foundation -o "$out/prefs_shared_test"
"$out/prefs_shared_test"
