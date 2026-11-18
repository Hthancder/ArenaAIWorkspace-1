#!/usr/bin/env bash
# Foundation-only fixtures; no API keys or network services are used.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
clang -DSX_TESTING=1 -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations -I Sources \
  tests/v12_core_test.m Sources/SXConfigIO.m Sources/SXMediaFormat.m Sources/SXNative.m Sources/SXNetwork.m Sources/SXStream.m \
  Sources/SXProviders.m Sources/SXPrefs.m Sources/SXLLM.m Sources/SXSTT.m \
  -framework Foundation -framework SystemConfiguration -o "$out/v12_core_test"
"$out/v12_core_test"
